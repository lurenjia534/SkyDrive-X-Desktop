use super::storage::{DownloadStore, SqliteDownloadStore};
use crate::api::drive::{
    download::download_drive_item_with_progress,
    models::{
        DownloadProgressUpdate, DownloadQueueState, DownloadStatus, DownloadTask,
        DriveDownloadResult, DriveItemSummary,
    },
};
use crate::db;
use directories::UserDirs;
use once_cell::sync::Lazy;
use std::{
    collections::{HashMap, HashSet},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, Sender},
        Arc, Mutex,
    },
    thread,
    time::{Instant, SystemTime, UNIX_EPOCH},
};

/// 全局下载管理器实例：避免多次初始化，同时方便在 FRB 桥接层与其他模块之间共享。
static DOWNLOAD_MANAGER: Lazy<DownloadManager> = Lazy::new(DownloadManager::new);

const INTERRUPTED_DOWNLOAD_MESSAGE: &str = "应用已关闭或异常退出，下载被中断，请重新下载";

/// 核心状态机：负责调度、下载线程管理、速度计算与事件广播。
#[derive(Clone)]
pub struct DownloadManager {
    state: Arc<Mutex<InnerState>>,
    store: Arc<dyn DownloadStore>,
    progress_meters: Arc<Mutex<HashMap<String, ProgressTick>>>,
    subscribers: Arc<Mutex<Vec<Sender<DownloadProgressUpdate>>>>,
    cancel_tokens: Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>,
}

/// 内部状态快照，仅在 rust 内部使用，避免 FRB 生成多余绑定。
#[derive(Clone, Default)]
struct InnerState {
    active: Vec<DownloadTask>,
    completed: Vec<DownloadTask>,
    failed: Vec<DownloadTask>,
}

/// 记录最近一次用来计算速度的快照（字节数 + 时间），便于平滑速率。
#[derive(Clone)]
struct ProgressTick {
    bytes_downloaded: u64,
    instant: Instant,
}

impl DownloadManager {
    fn new() -> Self {
        let manager = Self {
            state: Arc::new(Mutex::new(InnerState::default())),
            store: Arc::new(SqliteDownloadStore::default()),
            progress_meters: Arc::new(Mutex::new(HashMap::new())),
            subscribers: Arc::new(Mutex::new(Vec::new())),
            cancel_tokens: Arc::new(Mutex::new(HashMap::new())),
        };
        manager.restore_from_storage();
        manager
    }

    pub fn shared() -> Self {
        DOWNLOAD_MANAGER.clone()
    }

    /// 启动期间从数据库恢复最近的任务队列，确保重启后仍有上下文。
    fn restore_from_storage(&self) {
        let records = self.store.load();
        let mut active: Vec<DownloadTask> = Vec::new();
        let mut completed = Vec::new();
        let mut failed = Vec::new();
        for mut task in records {
            match task.status {
                DownloadStatus::InProgress => {
                    task.status = DownloadStatus::Failed;
                    task.completed_at = Some(current_timestamp());
                    if task.error_message.is_none() {
                        task.error_message = Some(INTERRUPTED_DOWNLOAD_MESSAGE.to_string());
                    }
                    self.store.upsert(&task);
                    failed.push(task);
                }
                DownloadStatus::Completed => completed.push(task),
                DownloadStatus::Failed => failed.push(task),
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

    /// 入队并启动下载线程，线程中会负责周期性推送进度。
    pub fn enqueue(
        &self,
        item: DriveItemSummary,
        target_dir: String,
        overwrite: bool,
    ) -> Result<DownloadQueueState, String> {
        if item.id.trim().is_empty() {
            return Err("drive item id is required".to_string());
        }
        if target_dir.trim().is_empty() {
            return Err("target directory is required".to_string());
        }

        let mut state = self
            .state
            .lock()
            .map_err(|_| "download manager poisoned".to_string())?;
        if state.active.iter().any(|task| task.item.id == item.id) {
            return Err("该文件已在下载队列中".to_string());
        }
        state.completed.retain(|task| task.item.id != item.id);
        state.failed.retain(|task| task.item.id != item.id);

        let task = DownloadTask {
            item: item.clone(),
            status: DownloadStatus::InProgress,
            started_at: current_timestamp(),
            completed_at: None,
            saved_path: None,
            size_label: item.size,
            bytes_downloaded: Some(0),
            error_message: None,
        };
        state.active.push(task.clone());
        drop(state);
        self.store.upsert(&task);

        let cancel_token = Arc::new(AtomicBool::new(false));
        self.register_cancel_token(&item.id, cancel_token.clone());

        let manager = self.clone();
        let item_id = item.id.clone();
        thread::spawn(move || {
            let progress_manager = manager.clone();
            let progress_item_id = item_id.clone();
            let progress_callback: Option<Box<dyn FnMut(u64, Option<u64>) + Send>> =
                Some(Box::new(move |downloaded: u64, expected: Option<u64>| {
                    progress_manager.report_progress(&progress_item_id, downloaded, expected);
                }));
            let result = download_drive_item_with_progress(
                item_id.clone(),
                target_dir,
                overwrite,
                progress_callback,
                Some(cancel_token.clone()),
            );
            match result {
                Ok(done) => manager.mark_success(&item_id, done),
                Err(err) => manager.mark_failure(&item_id, err),
            }
        });

        Ok(self.snapshot())
    }

    /// 下载成功后迁移任务到 completed，并更新存储/推送终态事件。
    fn mark_success(&self, item_id: &str, result: DriveDownloadResult) {
        let mut state = match self.state.lock() {
            Ok(guard) => guard,
            Err(err) => {
                eprintln!("[download-manager] failed to lock state on success: {err}");
                return;
            }
        };

        let mut updated_task = None;
        if let Some(position) = state.active.iter().position(|t| t.item.id == item_id) {
            let mut task = state.active.remove(position);
            task.status = DownloadStatus::Completed;
            task.completed_at = Some(current_timestamp());
            task.saved_path = Some(result.saved_path.clone());
            task.size_label = task.size_label.or(result.expected_size);
            task.bytes_downloaded = Some(result.bytes_downloaded);
            task.error_message = None;
            state.completed.insert(0, task.clone());
            updated_task = Some(task);
        }
        drop(state);
        if let Some(task) = updated_task {
            self.store.upsert(&task);
            self.clear_progress_meter(item_id);
            self.emit_progress_snapshot(
                item_id,
                task.bytes_downloaded.unwrap_or(result.bytes_downloaded),
                task.size_label.or(result.expected_size),
            );
            self.clear_cancel_token(item_id);
        }
    }

    /// 下载失败时迁移任务到 failed，并保留错误信息。
    fn mark_failure(&self, item_id: &str, err_msg: String) {
        let mut state = match self.state.lock() {
            Ok(guard) => guard,
            Err(err) => {
                eprintln!("[download-manager] failed to lock state on failure: {err}");
                return;
            }
        };

        let mut updated_task = None;
        if let Some(position) = state.active.iter().position(|t| t.item.id == item_id) {
            let mut task = state.active.remove(position);
            task.status = DownloadStatus::Failed;
            task.completed_at = Some(current_timestamp());
            task.error_message = Some(err_msg.clone());
            state.failed.insert(0, task.clone());
            updated_task = Some(task);
        } else {
            state.failed.retain(|task| task.item.id != item_id);
        }
        drop(state);
        if let Some(task) = updated_task {
            self.store.upsert(&task);
            self.clear_progress_meter(item_id);
            self.emit_progress_snapshot(
                item_id,
                task.bytes_downloaded.unwrap_or(0),
                task.size_label,
            );
            self.clear_cancel_token(item_id);
        }
    }

    /// 移除任意状态的任务，用于用户手动清理条目。
    pub fn remove(&self, item_id: &str) -> Result<DownloadQueueState, String> {
        let _ = self.signal_cancel(item_id);
        let mut state = self
            .state
            .lock()
            .map_err(|_| "download manager poisoned".to_string())?;
        state.active.retain(|task| task.item.id != item_id);
        state.completed.retain(|task| task.item.id != item_id);
        state.failed.retain(|task| task.item.id != item_id);
        let snapshot = (*state).clone();
        drop(state);
        self.store.remove(item_id);
        self.clear_progress_meter(item_id);
        Ok(snapshot.into())
    }

    /// 清除 completed/failed 历史记录；active 队列保持不变。
    pub fn clear_history(&self) -> Result<DownloadQueueState, String> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| "download manager poisoned".to_string())?;
        state.completed.clear();
        state.failed.clear();
        let snapshot = (*state).clone();
        drop(state);
        self.store.clear_history();
        self.prune_inactive_meters(&snapshot.active);
        Ok(snapshot.into())
    }

    /// 标记指定任务为取消状态，下载线程会在下一次轮询时终止。
    pub fn cancel(&self, item_id: &str) -> Result<DownloadQueueState, String> {
        if self.signal_cancel(item_id) {
            Ok(self.snapshot())
        } else {
            Err("未找到对应的下载任务或任务已结束".to_string())
        }
    }

    /// 仅清理失败任务，保留 active/completed 队列，方便 UI 一键清扫失败记录。
    pub fn clear_failed_tasks(&self) -> Result<DownloadQueueState, String> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| "download manager poisoned".to_string())?;
        if state.failed.is_empty() {
            return Ok((*state).clone().into());
        }
        let failed_ids: Vec<String> = state
            .failed
            .iter()
            .map(|task| task.item.id.clone())
            .collect();
        state.failed.clear();
        let snapshot = (*state).clone();
        drop(state);
        for id in failed_ids {
            self.store.remove(&id);
        }
        Ok(snapshot.into())
    }

    /// 返回当前状态的浅拷贝，供 FRB 直接转成 Dart 结构。
    pub fn snapshot(&self) -> DownloadQueueState {
        match self.state.lock() {
            Ok(guard) => (*guard).clone().into(),
            Err(_) => DownloadQueueState::default(),
        }
    }

    /// 下载线程调用的进度回调：更新内存+持久化，并向订阅者广播增量。
    fn report_progress(&self, item_id: &str, bytes_downloaded: u64, expected_size: Option<u64>) {
        let mut state = match self.state.lock() {
            Ok(guard) => guard,
            Err(err) => {
                eprintln!("[download-manager] failed to lock state on progress: {err}");
                return;
            }
        };

        let mut updated_task = None;
        if let Some(task) = state.active.iter_mut().find(|t| t.item.id == item_id) {
            task.bytes_downloaded = Some(bytes_downloaded);
            if expected_size.is_some() {
                task.size_label = expected_size;
            }
            updated_task = Some(task.clone());
        }
        drop(state);
        if let Some(task) = updated_task {
            self.store.upsert(&task);
            self.emit_progress_snapshot(item_id, bytes_downloaded, task.size_label);
        }
    }

    fn emit_progress_snapshot(
        &self,
        item_id: &str,
        bytes_downloaded: u64,
        expected_size: Option<u64>,
    ) {
        let speed = self.compute_speed_bps(item_id, bytes_downloaded);
        let update = DownloadProgressUpdate {
            item_id: item_id.to_string(),
            bytes_downloaded,
            expected_size,
            speed_bps: speed,
            timestamp_millis: current_timestamp(),
        };
        self.broadcast_update(update);
    }

    fn compute_speed_bps(&self, item_id: &str, bytes_downloaded: u64) -> Option<f64> {
        let mut meters = match self.progress_meters.lock() {
            Ok(guard) => guard,
            Err(err) => {
                eprintln!("[download-manager] failed to lock progress meters: {err}");
                return None;
            }
        };
        let now = Instant::now();
        if let Some(previous) = meters.insert(
            item_id.to_string(),
            ProgressTick {
                bytes_downloaded,
                instant: now,
            },
        ) {
            let delta_bytes = bytes_downloaded.saturating_sub(previous.bytes_downloaded);
            let elapsed = now.duration_since(previous.instant).as_secs_f64();
            if delta_bytes > 0 && elapsed > 0.0 {
                return Some(delta_bytes as f64 / elapsed);
            }
        }
        None
    }

    fn clear_progress_meter(&self, item_id: &str) {
        if let Ok(mut meters) = self.progress_meters.lock() {
            meters.remove(item_id);
        }
    }

    fn prune_inactive_meters(&self, active_tasks: &[DownloadTask]) {
        if let Ok(mut meters) = self.progress_meters.lock() {
            let active_ids: HashSet<String> = active_tasks
                .iter()
                .map(|task| task.item.id.clone())
                .collect();
            meters.retain(|id, _| active_ids.contains(id));
        }
    }

    fn register_cancel_token(&self, item_id: &str, token: Arc<AtomicBool>) {
        if let Ok(mut tokens) = self.cancel_tokens.lock() {
            tokens.insert(item_id.to_string(), token);
        }
    }

    fn clear_cancel_token(&self, item_id: &str) {
        if let Ok(mut tokens) = self.cancel_tokens.lock() {
            tokens.remove(item_id);
        }
    }

    fn signal_cancel(&self, item_id: &str) -> bool {
        if let Ok(tokens) = self.cancel_tokens.lock() {
            if let Some(token) = tokens.get(item_id) {
                token.store(true, Ordering::Relaxed);
                return true;
            }
        }
        false
    }

    /// 提供一个新的 channel 接收器，用于持续消费进度事件。
    pub fn subscribe_progress(&self) -> Receiver<DownloadProgressUpdate> {
        let (tx, rx) = mpsc::channel();
        if let Ok(mut subs) = self.subscribers.lock() {
            subs.push(tx.clone());
        }
        if let Ok(state) = self.state.lock() {
            for task in &state.active {
                if let Some(bytes) = task.bytes_downloaded {
                    let _ = tx.send(DownloadProgressUpdate {
                        item_id: task.item.id.clone(),
                        bytes_downloaded: bytes,
                        expected_size: task.size_label,
                        speed_bps: None,
                        timestamp_millis: current_timestamp(),
                    });
                }
            }
        }
        rx
    }

    fn broadcast_update(&self, update: DownloadProgressUpdate) {
        if let Ok(mut subs) = self.subscribers.lock() {
            subs.retain_mut(|sender| sender.send(update.clone()).is_ok());
        }
    }
}

impl From<InnerState> for DownloadQueueState {
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

pub fn download_queue_state() -> DownloadQueueState {
    DownloadManager::shared().snapshot()
}

pub fn enqueue_download_task(
    item: DriveItemSummary,
    target_dir: String,
    overwrite: bool,
) -> Result<DownloadQueueState, String> {
    DownloadManager::shared().enqueue(item, target_dir, overwrite)
}

pub fn remove_download_task(item_id: &str) -> Result<DownloadQueueState, String> {
    DownloadManager::shared().remove(item_id)
}

pub fn cancel_download_task(item_id: &str) -> Result<DownloadQueueState, String> {
    DownloadManager::shared().cancel(item_id)
}

const DOWNLOAD_DIR_KEY: &str = "download_directory";

pub fn get_download_directory() -> Result<String, String> {
    if let Some(value) = db::get_setting(DOWNLOAD_DIR_KEY)? {
        return Ok(value);
    }
    default_download_directory()
}

pub fn set_download_directory(path: String) -> Result<String, String> {
    if path.trim().is_empty() {
        return Err("download directory cannot be empty".to_string());
    }
    db::set_setting(DOWNLOAD_DIR_KEY, &path)?;
    Ok(path)
}

fn default_download_directory() -> Result<String, String> {
    if let Some(user_dirs) = UserDirs::new() {
        let base = user_dirs.download_dir().unwrap_or(user_dirs.home_dir());
        return Ok(base.join("skydrivex").to_string_lossy().into_owned());
    }
    Err("failed to resolve default download directory".to_string())
}

pub fn clear_download_history() -> Result<DownloadQueueState, String> {
    DownloadManager::shared().clear_history()
}

pub fn clear_failed_download_tasks() -> Result<DownloadQueueState, String> {
    DownloadManager::shared().clear_failed_tasks()
}

pub fn subscribe_progress() -> Receiver<DownloadProgressUpdate> {
    DownloadManager::shared().subscribe_progress()
}
