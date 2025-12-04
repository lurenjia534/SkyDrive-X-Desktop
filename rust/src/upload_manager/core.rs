// 上传队列核心：对标 download_manager，负责调度、状态管理、持久化与进度广播。
use super::storage::{SqliteUploadStore, UploadStore};
use crate::api::drive::{
    models::{UploadProgressUpdate, UploadQueueState, UploadStatus, UploadTask},
    upload::{
        create_upload_session, get_upload_session_status, upload_large_file_with_hooks,
        upload_small_file_with_hooks, UploadSessionResponse,
    },
};
use once_cell::sync::Lazy;
use std::{
    collections::{HashMap, HashSet, VecDeque},
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

// 应用异常退出后，未完成的任务会被标记为失败并附上该提示。
const INTERRUPTED_UPLOAD_MESSAGE: &str = "应用已关闭或异常退出，上传被中断，请重新上传";
const CANCELLED_UPLOAD_MESSAGE: &str = "上传已取消";
const CANCELLED_ERR_FLAG: &str = "upload cancelled";
// 进度广播 channel 的缓冲大小，防止无界内存增长。
const PROGRESS_CHANNEL_CAP: usize = 64;
// 持久化节流：至少累积多少字节或间隔多久才写入 SQLite。
const PERSIST_BYTES_THRESHOLD: u64 = 256 * 1024;
const PERSIST_INTERVAL: std::time::Duration = std::time::Duration::from_secs(1);
// 速度采样的最小时间间隔，避免瞬时过短导致虚高。
const SPEED_SAMPLE_MIN_INTERVAL: std::time::Duration = std::time::Duration::from_millis(200);
// 速度窗口时长，用最近一段时间的累积量平滑瞬时波动。
const SPEED_WINDOW: std::time::Duration = std::time::Duration::from_secs(5);

/// 上传管理器实例，提供队列/进度/取消等操作。
#[derive(Clone)]
pub struct UploadManager {
    state: Arc<Mutex<InnerState>>,
    store: Arc<dyn UploadStore>,
    /// 速度估算缓存
    progress_meters: Arc<Mutex<HashMap<String, ProgressTick>>>,
    /// 写库节流标记
    persist_markers: Arc<Mutex<HashMap<String, PersistMarker>>>,
    /// 订阅者列表
    subscribers: Arc<Mutex<Vec<SyncSender<UploadProgressUpdate>>>>,
    cancel_tokens: Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>,
    /// 控制并发上传数量
    concurrency_guard: Arc<Semaphore>,
}

/// 内存态快照，避免直接暴露给 FRB。
#[derive(Clone, Default)]
struct InnerState {
    active: Vec<UploadTask>,
    completed: Vec<UploadTask>,
    failed: Vec<UploadTask>,
}

/// 速度计算用采样点，包含平滑速度。
#[derive(Clone)]
struct ProgressTick {
    bytes_uploaded: u64,
    instant: Instant,
    smoothed_bps: Option<f64>,
    samples: VecDeque<(Instant, u64)>,
}

/// 持久化节流标记。
struct PersistMarker {
    bytes_uploaded: u64,
    instant: Instant,
}

impl UploadManager {
    /// 构造全局单例，读取持久化记录并归档未完成任务。
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

    /// 获取可克隆的全局实例。
    pub fn shared() -> Self {
        UPLOAD_MANAGER.clone()
    }

    /// 重启恢复：对有会话的未完成任务尝试恢复，否则标记为失败，避免“假活跃”。
    fn restore_from_storage(&self) {
        let records = self.store.load();
        let mut active: Vec<UploadTask> = Vec::new();
        let mut completed = Vec::new();
        let mut failed = Vec::new();
        let mut resume_tasks = Vec::new();
        for mut task in records {
            match task.status {
                UploadStatus::InProgress => {
                    if task.session_url.is_some() && task.size.is_some() {
                        resume_tasks.push(task.clone());
                        active.push(task);
                    } else {
                        task.status = UploadStatus::Failed;
                        task.completed_at = Some(current_timestamp());
                        if task.error_message.is_none() {
                            task.error_message = Some(INTERRUPTED_UPLOAD_MESSAGE.to_string());
                        }
                        self.store.upsert(&task);
                        failed.push(task);
                    }
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

        // 异步恢复仍未完成的大文件上传。
        for task in resume_tasks {
            self.resume_large_upload(task);
        }
    }

    /// 入队小文件上传：生成任务、持久化、启动上传线程并返回最新队列。
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
            let progress_cb: Option<Box<dyn FnMut(u64, Option<u64>) + Send>> = Some(Box::new({
                let manager = manager.clone();
                let task_id = task_id.clone();
                move |uploaded, total| {
                    manager.report_progress(&task_id, uploaded, total);
                }
            }));
            let result = upload_small_file_with_hooks(
                parent_id,
                file_name,
                bytes,
                overwrite,
                Some(cancel_token.clone()),
                progress_cb,
            );
            match result {
                Ok(summary) => manager.mark_success(&task_id, summary.id),
                Err(err) => {
                    if err == CANCELLED_ERR_FLAG {
                        manager.mark_cancelled(&task_id);
                    } else {
                        manager.mark_failure(&task_id, err);
                    }
                }
            }
        });

        Ok(self.snapshot())
    }

    /// 入队大文件上传（分片）：读取本地文件路径，创建 Graph 会话并上传。
    pub fn enqueue_large_file(
        &self,
        parent_id: Option<String>,
        file_name: String,
        local_path: String,
        overwrite: bool,
    ) -> Result<UploadQueueState, String> {
        if file_name.trim().is_empty() {
            return Err("file name is required".to_string());
        }
        let file_meta = std::fs::metadata(&local_path)
            .map_err(|e| format!("无法读取文件大小: {e}"))?;
        let total_size = file_meta.len();
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
            local_path: local_path.clone(),
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
            let result = manager.run_large_upload_task(
                &task_id,
                parent_id,
                file_name,
                local_path,
                total_size,
                overwrite,
                cancel_token.clone(),
            );
            match result {
                Ok(remote_id) => manager.mark_success(&task_id, remote_id),
                Err(err) => {
                    if err == CANCELLED_ERR_FLAG {
                        manager.mark_cancelled(&task_id);
                    } else {
                        manager.mark_failure(&task_id, err);
                    }
                }
            }
        });

        Ok(self.snapshot())
    }

    /// 恢复已有会话的大文件上传，在应用重启或恢复时调用。
    fn resume_large_upload(&self, task: UploadTask) {
        if task.size.is_none() || task.session_url.is_none() {
            return;
        }
        let cancel_token = Arc::new(AtomicBool::new(false));
        self.register_cancel_token(&task.task_id, cancel_token.clone());
        let manager = self.clone();
        thread::spawn(move || {
            let _permit = manager.concurrency_guard.acquire();
            let result = manager.run_large_upload_task(
                &task.task_id,
                task.parent_id.clone(),
                task.file_name.clone(),
                task.local_path.clone(),
                task.size.unwrap(),
                false, // overwrite 已体现在既有会话，不再使用
                cancel_token.clone(),
            );
            match result {
                Ok(remote_id) => manager.mark_success(&task.task_id, remote_id),
                Err(err) => {
                    if err == CANCELLED_ERR_FLAG {
                        manager.mark_cancelled(&task.task_id);
                    } else {
                        manager.mark_failure(&task.task_id, err);
                    }
                }
            }
        });
    }

    /// 实际执行大文件分片上传，含会话创建/恢复与进度上报。
    fn run_large_upload_task(
        &self,
        task_id: &str,
        parent_id: Option<String>,
        file_name: String,
        local_path: String,
        total_size: u64,
        overwrite: bool,
        cancel_token: Arc<AtomicBool>,
    ) -> Result<String, String> {
        if !std::path::Path::new(&local_path).exists() {
            return Err("local file not found".to_string());
        }
        // 复用已有会话或创建新会话。
        let mut upload_url = {
            let state = recover_lock(&self.state);
            state
                .active
                .iter()
                .find(|t| t.task_id == task_id)
                .and_then(|t| t.session_url.clone())
        };
        if upload_url.is_none() {
            let session = create_upload_session(parent_id.clone(), &file_name, overwrite)?;
            upload_url = session.upload_url.clone();
            self.update_task_session(task_id, &session);
        }
        let upload_url = upload_url.ok_or_else(|| "missing upload session url".to_string())?;

        // 查询会话状态，决定续传起点。
        let mut start_offset = {
            let state = recover_lock(&self.state);
            state
                .active
                .iter()
                .find(|t| t.task_id == task_id)
                .and_then(|t| t.bytes_uploaded)
                .unwrap_or(0)
        };
        if let Ok(status) = get_upload_session_status(&upload_url) {
            if let Some(next) = parse_next_start(&status.next_expected_ranges) {
                start_offset = next;
            }
            // 如果服务端已返回最终 item，直接成功。
            if let Some(item) = status.drive_item {
                return Ok(item.id);
            }
        }

        let progress_cb: Option<Box<dyn FnMut(u64, Option<u64>) + Send>> = Some(Box::new({
            let manager = self.clone();
            let task_id = task_id.to_string();
            move |uploaded, total| {
                manager.report_progress(&task_id, uploaded, total);
            }
        }));

        let summary = upload_large_file_with_hooks(
            upload_url,
            &local_path,
            total_size,
            start_offset,
            cancel_token,
            progress_cb,
        )?;
        Ok(summary.id)
    }

    /// 上传成功：迁移到 completed，写库，推送终态进度。
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

    /// 上传失败：迁移到 failed，保留错误信息。
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

    /// 用户取消：记录取消状态，避免展示为失败。
    fn mark_cancelled(&self, task_id: &str) {
        let mut state = match self.state.lock() {
            Ok(guard) => guard,
            Err(poison) => {
                eprintln!("[upload-manager] state lock poisoned on cancel; recovering");
                poison.into_inner()
            }
        };
        let mut updated = None;
        if let Some(pos) = state.active.iter().position(|t| t.task_id == task_id) {
            let mut task = state.active.remove(pos);
            task.status = UploadStatus::Cancelled;
            task.completed_at = Some(current_timestamp());
            task.error_message = Some(CANCELLED_UPLOAD_MESSAGE.to_string());
            state.failed.insert(0, task.clone());
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

    /// 标记取消：上层 UI 可即时反馈，“真取消”取决于底层上传是否可中断。
    pub fn cancel(&self, task_id: &str) -> Result<UploadQueueState, String> {
        if self.signal_cancel(task_id) {
            Ok(self.snapshot())
        } else {
            Err("未找到对应的上传任务或已结束".to_string())
        }
    }

    /// 移除任意状态的任务。
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
        self.clear_cancel_token(task_id);
        Ok(snapshot.into())
    }

    /// 清空历史记录（completed/failed），active 保留。
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

    /// 清空 failed 任务，并删除持久化记录。
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

    /// 返回当前队列快照。
    pub fn snapshot(&self) -> UploadQueueState {
        self.state
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clone()
            .into()
    }

    /// 进度回调：更新内存/持久化，推送进度事件。
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
                smoothed_bps: None,
                samples: {
                    let mut dq = VecDeque::new();
                    dq.push_back((now, bytes_uploaded));
                    dq
                },
            });
        let delta_bytes = bytes_uploaded.saturating_sub(entry.bytes_uploaded);
        let elapsed = now.duration_since(entry.instant);
        if delta_bytes == 0 || elapsed < SPEED_SAMPLE_MIN_INTERVAL {
            return entry.smoothed_bps;
        }
        entry.bytes_uploaded = bytes_uploaded;
        entry.instant = now;
        entry.samples.push_back((now, bytes_uploaded));
        // 滑动窗口：移除窗口外的采样点。
        while let Some((ts, _)) = entry.samples.front() {
            if now.duration_since(*ts) > SPEED_WINDOW {
                entry.samples.pop_front();
            } else {
                break;
            }
        }
        let window_bps = match (entry.samples.front(), entry.samples.back()) {
            (Some((start_t, start_bytes)), Some((end_t, end_bytes))) if end_t > start_t => {
                let span = end_t.duration_since(*start_t).as_secs_f64();
                if span > 0.0 {
                    let delta = end_bytes.saturating_sub(*start_bytes) as f64;
                    Some(delta / span)
                } else {
                    None
                }
            }
            _ => None,
        };
        let inst = delta_bytes as f64 / elapsed.as_secs_f64();
        // 组合窗口平均与即时速率，既能跟上上升也避免尖峰。
        let candidate = match window_bps {
            Some(avg) => avg.max(inst * 0.6),
            None => inst,
        };
        let smooth = match entry.smoothed_bps {
            Some(prev) => prev * 0.5 + candidate * 0.5,
            None => candidate,
        };
        entry.smoothed_bps = Some(smooth);
        Some(smooth)
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

    fn update_task_session(&self, task_id: &str, session: &UploadSessionResponse) {
        let mut state = recover_lock(&self.state);
        let mut cloned: Option<UploadTask> = None;
        if let Some(task) = state.active.iter_mut().find(|t| t.task_id == task_id) {
            task.session_url = session.upload_url.clone();
            cloned = Some(task.clone());
        }
        drop(state);
        if let Some(task) = cloned {
            self.store.upsert(&task);
        }
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

fn parse_next_start(next_expected: &Option<Vec<String>>) -> Option<u64> {
    let raw = next_expected.as_ref()?.first()?;
    if let Some((start, _)) = raw.split_once('-') {
        return start.parse::<u64>().ok();
    }
    raw.parse::<u64>().ok()
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
