use super::storage::{SqliteUploadStore, UploadStore};
use crate::api::drive::{
    models::{UploadProgressUpdate, UploadQueueState, UploadStatus, UploadTask},
    upload::upload_small_file,
};
use once_cell::sync::Lazy;
use std::{
    collections::{HashMap, HashSet},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, SyncSender, TrySendError},
        Arc, Condvar, Mutex,
    },
    thread,
    time::{Instant, SystemTime, UNIX_EPOCH},
};
use uuid::Uuid;

static UPLOAD_MANAGER: Lazy<UploadManager> = Lazy::new(UploadManager::new);

const INTERRUPTED_UPLOAD_MESSAGE: &str = "应用已关闭或异常退出，上传被中断，请重新上传";
const PROGRESS_CHANNEL_CAP: usize = 64;
const PERSIST_BYTES_THRESHOLD: u64 = 256 * 1024;
const PERSIST_INTERVAL: std::time::Duration = std::time::Duration::from_secs(1);
const SPEED_SAMPLE_MIN_INTERVAL: std::time::Duration = std::time::Duration::from_millis(300);

#[derive(Clone)]
pub struct UploadManager {
    state: Arc<Mutex<InnerState>>,
    store: Arc<dyn UploadStore>,
    progress_meters: Arc<Mutex<HashMap<String, ProgressTick>>>,
    persist_markers: Arc<Mutex<HashMap<String, PersistMarker>>>,
    subscribers: Arc<Mutex<Vec<SyncSender<UploadProgressUpdate>>>>,
    cancel_tokens: Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>,
    concurrency_guard: Arc<Semaphore>,
}

#[derive(Clone, Default)]
struct InnerState {
    active: Vec<UploadTask>,
    completed: Vec<UploadTask>,
    failed: Vec<UploadTask>,
}

#[derive(Clone)]
struct ProgressTick {
    bytes_uploaded: u64,
    instant: Instant,
}

struct PersistMarker {
    bytes_uploaded: u64,
    instant: Instant,
}

impl UploadManager {
    fn new() -> Self {
        let manager = Self {
            state: Arc::new(Mutex::new(InnerState::default())),
            store: Arc::new(SqliteUploadStore::default()),
            progress_meters: Arc::new(Mutex::new(HashMap::new())),
            persist_markers: Arc::new(Mutex::new(HashMap::new())),
            subscribers: Arc::new(Mutex::new(Vec::new())),
            cancel_tokens: Arc::new(Mutex::new(HashMap::new())),
            concurrency_guard: Arc::new(Semaphore::new(2)),
        };
        manager.restore_from_storage();
        manager
    }

    pub fn shared() -> Self {
        UPLOAD_MANAGER.clone()
    }

    fn restore_from_storage(&self) {
        let records = self.store.load();
        let mut active: Vec<UploadTask> = Vec::new();
        let mut completed = Vec::new();
        let mut failed = Vec::new();
        for mut task in records {
            match task.status {
                UploadStatus::InProgress => {
                    task.status = UploadStatus::Failed;
                    task.completed_at = Some(current_timestamp());
                    if task.error_message.is_none() {
                        task.error_message = Some(INTERRUPTED_UPLOAD_MESSAGE.to_string());
                    }
                    self.store.upsert(&task);
                    failed.push(task);
                }
                UploadStatus::Completed => completed.push(task),
                UploadStatus::Failed | UploadStatus::Cancelled => failed.push(task),
            }
        }
        active.sort_by_key(|task| task.started_at);
        completed.sort_by_key(|task| std::cmp::Reverse(task.completed_at));
        failed.sort_by_key(|task| std::cmp::Reverse(task.completed_at));
        if let Ok(mut state) = self.state.lock() {
            state.active = active;
            state.completed = completed;
            state.failed = failed;
        }
    }

    pub fn enqueue_small_file(
        &self,
        parent_id: Option<String>,
        file_name: String,
        local_path: String,
        bytes: Vec<u8>,
        overwrite: bool,
    ) -> Result<UploadQueueState, String> {
        if file_name.trim().is_empty() {
            return Err("file name is required".to_string());
        }
        let total_size = bytes.len() as u64;
        let task_id = Uuid::new_v4().to_string();
        let mut state = self.state.lock().unwrap_or_else(|p| p.into_inner());
        if state
            .active
            .iter()
            .any(|t| t.file_name == file_name && t.parent_id == parent_id)
        {
            return Err("同名文件已在上传队列中".to_string());
        }
        state
            .failed
            .retain(|t| t.file_name != file_name || t.parent_id != parent_id);
        state
            .completed
            .retain(|t| t.file_name != file_name || t.parent_id != parent_id);

        let task = UploadTask {
            task_id: task_id.clone(),
            file_name: file_name.clone(),
            local_path,
            size: Some(total_size),
            mime_type: None,
            parent_id: parent_id.clone(),
            remote_id: None,
            status: UploadStatus::InProgress,
            started_at: current_timestamp(),
            completed_at: None,
            bytes_uploaded: Some(0),
            error_message: None,
            session_url: None,
        };
        state.active.push(task.clone());
        drop(state);
        self.store.upsert(&task);

        let cancel_token = Arc::new(AtomicBool::new(false));
        self.register_cancel_token(&task_id, cancel_token.clone());

        let manager = self.clone();
        thread::spawn(move || {
            let _permit = manager.concurrency_guard.acquire();
            let result = upload_small_file(parent_id, file_name, bytes, overwrite);
            match result {
                Ok(summary) => {
                    manager.report_progress(&task_id, total_size, Some(total_size));
                    manager.mark_success(&task_id, summary.id);
                }
                Err(err) => manager.mark_failure(&task_id, err),
            }
        });

        Ok(self.snapshot())
    }

    fn mark_success(&self, task_id: &str, remote_id: String) {
        let mut state = match self.state.lock() {
            Ok(guard) => guard,
            Err(poison) => {
                eprintln!("[upload-manager] state lock poisoned on success; recovering");
                poison.into_inner()
            }
        };
        let mut updated = None;
        if let Some(pos) = state.active.iter().position(|t| t.task_id == task_id) {
            let mut task = state.active.remove(pos);
            task.status = UploadStatus::Completed;
            task.completed_at = Some(current_timestamp());
            task.remote_id = Some(remote_id);
            task.error_message = None;
            state.completed.insert(0, task.clone());
            updated = Some(task);
        }
        drop(state);
        if let Some(task) = updated {
            self.store.upsert(&task);
            self.clear_progress_meter(task_id);
            self.emit_progress_snapshot(task_id, task.bytes_uploaded.unwrap_or(0), task.size);
            self.clear_cancel_token(task_id);
        }
    }

    fn mark_failure(&self, task_id: &str, err: String) {
        let mut state = match self.state.lock() {
            Ok(guard) => guard,
            Err(poison) => {
                eprintln!("[upload-manager] state lock poisoned on failure; recovering");
                poison.into_inner()
            }
        };
        let mut updated = None;
        if let Some(pos) = state.active.iter().position(|t| t.task_id == task_id) {
            let mut task = state.active.remove(pos);
            task.status = UploadStatus::Failed;
            task.completed_at = Some(current_timestamp());
            task.error_message = Some(err.clone());
            state.failed.insert(0, task.clone());
            updated = Some(task);
        } else {
            state.failed.retain(|t| t.task_id != task_id);
        }
        drop(state);
        if let Some(task) = updated {
            self.store.upsert(&task);
            self.clear_progress_meter(task_id);
            self.emit_progress_snapshot(task_id, task.bytes_uploaded.unwrap_or(0), task.size);
            self.clear_cancel_token(task_id);
        }
    }

    pub fn cancel(&self, task_id: &str) -> Result<UploadQueueState, String> {
        if self.signal_cancel(task_id) {
            Ok(self.snapshot())
        } else {
            Err("未找到对应的上传任务或已结束".to_string())
        }
    }

    pub fn remove(&self, task_id: &str) -> Result<UploadQueueState, String> {
        let _ = self.signal_cancel(task_id);
        let mut state = self.state.lock().unwrap_or_else(|p| p.into_inner());
        state.active.retain(|t| t.task_id != task_id);
        state.completed.retain(|t| t.task_id != task_id);
        state.failed.retain(|t| t.task_id != task_id);
        let snapshot = (*state).clone();
        drop(state);
        self.store.remove(task_id);
        self.clear_progress_meter(task_id);
        Ok(snapshot.into())
    }

    pub fn clear_history(&self) -> Result<UploadQueueState, String> {
        let mut state = self.state.lock().unwrap_or_else(|p| p.into_inner());
        state.completed.clear();
        state.failed.clear();
        let snapshot = (*state).clone();
        drop(state);
        self.store.clear_history();
        self.prune_inactive_trackers(&snapshot.active);
        Ok(snapshot.into())
    }

    pub fn clear_failed_tasks(&self) -> Result<UploadQueueState, String> {
        let mut state = self.state.lock().unwrap_or_else(|p| p.into_inner());
        if state.failed.is_empty() {
            return Ok((*state).clone().into());
        }
        let failed_ids: Vec<String> = state.failed.iter().map(|t| t.task_id.clone()).collect();
        state.failed.clear();
        let snapshot = (*state).clone();
        drop(state);
        for id in failed_ids {
            self.store.remove(&id);
        }
        Ok(snapshot.into())
    }

    pub fn snapshot(&self) -> UploadQueueState {
        self.state
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clone()
            .into()
    }

    fn report_progress(&self, task_id: &str, bytes_uploaded: u64, total_size: Option<u64>) {
        let mut state = match self.state.lock() {
            Ok(guard) => guard,
            Err(poison) => {
                eprintln!("[upload-manager] state lock poisoned on progress; recovering");
                poison.into_inner()
            }
        };
        let mut updated = None;
        if let Some(task) = state.active.iter_mut().find(|t| t.task_id == task_id) {
            task.bytes_uploaded = Some(bytes_uploaded);
            if total_size.is_some() {
                task.size = total_size;
            }
            updated = Some(task.clone());
        }
        drop(state);
        if let Some(task) = updated {
            if self.should_persist_progress(task_id, bytes_uploaded) {
                self.store.upsert(&task);
            }
            self.emit_progress_snapshot(task_id, bytes_uploaded, task.size);
        }
    }

    fn emit_progress_snapshot(&self, task_id: &str, bytes_uploaded: u64, total_size: Option<u64>) {
        let speed = self.compute_speed_bps(task_id, bytes_uploaded);
        let update = UploadProgressUpdate {
            task_id: task_id.to_string(),
            bytes_uploaded,
            expected_size: total_size,
            speed_bps: speed,
            timestamp_millis: current_timestamp(),
        };
        self.broadcast_update(update);
    }

    fn compute_speed_bps(&self, task_id: &str, bytes_uploaded: u64) -> Option<f64> {
        let now = Instant::now();
        let mut meters = recover_lock(&self.progress_meters);
        let entry = meters
            .entry(task_id.to_string())
            .or_insert_with(|| ProgressTick {
                bytes_uploaded,
                instant: now,
            });
        let delta_bytes = bytes_uploaded.saturating_sub(entry.bytes_uploaded);
        let elapsed = now.duration_since(entry.instant);
        if delta_bytes == 0 || elapsed < SPEED_SAMPLE_MIN_INTERVAL {
            return None;
        }
        entry.bytes_uploaded = bytes_uploaded;
        entry.instant = now;
        Some(delta_bytes as f64 / elapsed.as_secs_f64())
    }

    fn clear_progress_meter(&self, task_id: &str) {
        let mut meters = recover_lock(&self.progress_meters);
        meters.remove(task_id);
        drop(meters);
        self.clear_persist_marker(task_id);
    }

    fn prune_inactive_trackers(&self, active_tasks: &[UploadTask]) {
        let active_ids: HashSet<String> = active_tasks.iter().map(|t| t.task_id.clone()).collect();
        let mut meters = recover_lock(&self.progress_meters);
        meters.retain(|id, _| active_ids.contains(id));
        drop(meters);
        let mut markers = recover_lock(&self.persist_markers);
        markers.retain(|id, _| active_ids.contains(id));
    }

    fn register_cancel_token(&self, task_id: &str, token: Arc<AtomicBool>) {
        let mut tokens = recover_lock(&self.cancel_tokens);
        tokens.insert(task_id.to_string(), token);
    }

    fn clear_cancel_token(&self, task_id: &str) {
        let mut tokens = recover_lock(&self.cancel_tokens);
        tokens.remove(task_id);
    }

    fn signal_cancel(&self, task_id: &str) -> bool {
        let tokens = recover_lock(&self.cancel_tokens);
        if let Some(token) = tokens.get(task_id) {
            token.store(true, Ordering::Relaxed);
            return true;
        }
        false
    }

    fn should_persist_progress(&self, task_id: &str, bytes_uploaded: u64) -> bool {
        let now = Instant::now();
        let mut inserted = false;
        let mut markers = recover_lock(&self.persist_markers);
        let entry = markers.entry(task_id.to_string()).or_insert_with(|| {
            inserted = true;
            PersistMarker {
                bytes_uploaded,
                instant: now,
            }
        });
        if inserted {
            return true;
        }
        let delta_bytes = bytes_uploaded.saturating_sub(entry.bytes_uploaded);
        let elapsed = now.duration_since(entry.instant);
        if delta_bytes >= PERSIST_BYTES_THRESHOLD || elapsed >= PERSIST_INTERVAL {
            entry.bytes_uploaded = bytes_uploaded;
            entry.instant = now;
            true
        } else {
            false
        }
    }

    fn clear_persist_marker(&self, task_id: &str) {
        let mut markers = recover_lock(&self.persist_markers);
        markers.remove(task_id);
    }

    pub fn subscribe_progress(&self) -> Receiver<UploadProgressUpdate> {
        let (tx, rx) = mpsc::sync_channel(PROGRESS_CHANNEL_CAP);
        let mut subs = recover_lock(&self.subscribers);
        subs.push(tx.clone());
        drop(subs);

        let state = recover_lock(&self.state);
        for task in &state.active {
            if let Some(bytes) = task.bytes_uploaded {
                let _ = tx.try_send(UploadProgressUpdate {
                    task_id: task.task_id.clone(),
                    bytes_uploaded: bytes,
                    expected_size: task.size,
                    speed_bps: None,
                    timestamp_millis: current_timestamp(),
                });
            }
        }
        rx
    }

    fn broadcast_update(&self, update: UploadProgressUpdate) {
        let mut subs = recover_lock(&self.subscribers);
        subs.retain_mut(|sender| match sender.try_send(update.clone()) {
            Ok(_) => true,
            Err(TrySendError::Full(_)) => true,
            Err(TrySendError::Disconnected(_)) => false,
        });
    }
}

impl From<InnerState> for UploadQueueState {
    fn from(value: InnerState) -> Self {
        Self {
            active: value.active,
            completed: value.completed,
            failed: value.failed,
        }
    }
}

fn current_timestamp() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or_default()
}

fn recover_lock<'a, T>(mutex: &'a Mutex<T>) -> std::sync::MutexGuard<'a, T> {
    match mutex.lock() {
        Ok(g) => g,
        Err(poison) => poison.into_inner(),
    }
}

struct Semaphore {
    state: Mutex<SemaphoreState>,
    cvar: Condvar,
}

struct SemaphoreState {
    available: usize,
    max: usize,
}

impl Semaphore {
    fn new(max: usize) -> Self {
        Self {
            state: Mutex::new(SemaphoreState {
                available: max,
                max,
            }),
            cvar: Condvar::new(),
        }
    }

    fn acquire(&self) -> SemaphorePermit<'_> {
        let mut state = self.state.lock().unwrap_or_else(|p| p.into_inner());
        while state.available == 0 {
            state = self.cvar.wait(state).unwrap_or_else(|p| p.into_inner());
        }
        state.available -= 1;
        SemaphorePermit { semaphore: self }
    }

    fn release(&self) {
        let mut state = self.state.lock().unwrap_or_else(|p| p.into_inner());
        if state.available < state.max {
            state.available += 1;
            self.cvar.notify_one();
        }
    }
}

struct SemaphorePermit<'a> {
    semaphore: &'a Semaphore,
}

impl<'a> Drop for SemaphorePermit<'a> {
    fn drop(&mut self) {
        self.semaphore.release();
    }
}
