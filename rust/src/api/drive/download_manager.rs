use super::{
    download::download_drive_item_with_progress,
    models::{
        DownloadQueueState, DownloadStatus, DownloadTask, DriveDownloadResult, DriveItemSummary,
    },
};
use crate::db::{self, DownloadTaskRecord};
use once_cell::sync::Lazy;
use std::{
    sync::{Arc, Mutex},
    thread,
    time::{SystemTime, UNIX_EPOCH},
};

const STATUS_IN_PROGRESS: i64 = 0;
const STATUS_COMPLETED: i64 = 1;
const STATUS_FAILED: i64 = 2;

/// 全局下载管理器实例；通过 `Lazy` 确保只初始化一次，并能在线程之间安全共享。
static DOWNLOAD_MANAGER: Lazy<DownloadManager> = Lazy::new(DownloadManager::new);

/// 负责调度下载任务与维护队列状态的核心结构。
#[derive(Clone)]
pub struct DownloadManager {
    state: Arc<Mutex<InnerState>>,
}

#[flutter_rust_bridge::frb(ignore)]
#[derive(Clone, Default)]
struct InnerState {
    active: Vec<DownloadTask>,
    completed: Vec<DownloadTask>,
    failed: Vec<DownloadTask>,
}

impl DownloadManager {
    fn new() -> Self {
        let manager = Self {
            state: Arc::new(Mutex::new(InnerState::default())),
        };
        manager.restore_from_storage();
        manager
    }

    fn shared() -> Self {
        DOWNLOAD_MANAGER.clone()
    }

    fn restore_from_storage(&self) {
        match db::load_download_tasks() {
            Ok(records) => {
                let mut active = Vec::new();
                let mut completed = Vec::new();
                let mut failed = Vec::new();
                for record in records {
                    match record.status {
                        STATUS_IN_PROGRESS => {
                            active.push(task_from_record(record));
                        }
                        STATUS_COMPLETED => {
                            completed.push(task_from_record(record));
                        }
                        STATUS_FAILED => {
                            failed.push(task_from_record(record));
                        }
                        other => {
                            eprintln!(
                                "[drive-download] encountered unknown status {other} for {}",
                                record.item_id
                            );
                        }
                    }
                }
                active.sort_by_key(|task| task.started_at);
                completed.sort_by(|a, b| {
                    b.completed_at
                        .unwrap_or(0)
                        .cmp(&a.completed_at.unwrap_or(0))
                });
                failed.sort_by(|a, b| {
                    b.completed_at
                        .unwrap_or(0)
                        .cmp(&a.completed_at.unwrap_or(0))
                });

                if let Ok(mut state) = self.state.lock() {
                    state.active = active;
                    state.completed = completed;
                    state.failed = failed;
                }
            }
            Err(err) => {
                eprintln!("[drive-download] failed to restore queue from storage: {err}");
            }
        }
    }

    fn persist_task(&self, task: &DownloadTask) {
        let record = record_from_task(task);
        if let Err(err) = db::upsert_download_task(&record) {
            eprintln!(
                "[drive-download] failed to persist task {}: {err}",
                task.item.id
            );
        }
    }

    fn remove_task_from_storage(&self, item_id: &str) {
        if let Err(err) = db::delete_download_task(item_id) {
            eprintln!("[drive-download] failed to delete task {item_id}: {err}");
        }
    }

    fn clear_history_from_storage(&self) {
        if let Err(err) = db::clear_finished_download_tasks(STATUS_IN_PROGRESS) {
            eprintln!("[drive-download] failed to clear download history: {err}");
        }
    }

    /// 写入任务并启动后续下载线程；返回最新队列快照。
    fn enqueue_internal(
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
            started_at: now_millis(),
            completed_at: None,
            saved_path: None,
            size_label: item.size,
            bytes_downloaded: Some(0),
            error_message: None,
        };
        state.active.push(task.clone());
        drop(state);
        self.persist_task(&task);

        let manager = self.clone();
        let item_id = item.id.clone();
        thread::spawn(move || {
            let progress_manager = manager.clone();
            let progress_item_id = item_id.clone();
            let progress_callback: Option<Box<dyn FnMut(u64, Option<u64>) + Send>> =
                Some(Box::new(move |downloaded: u64, expected: Option<u64>| {
                    progress_manager.report_progress(&progress_item_id, downloaded, expected);
                }));
            // 将请求委托给带进度的下载函数，事件在闭包里推送回管理器。
            let result = download_drive_item_with_progress(
                item_id.clone(),
                target_dir,
                overwrite,
                progress_callback,
            );
            match result {
                Ok(done) => manager.mark_success(&item_id, done),
                Err(err) => manager.mark_failure(&item_id, err),
            }
        });

        Ok(self.snapshot())
    }

    /// 下载完成后将任务从 active 移动到 completed，并记录保存路径。
    fn mark_success(&self, item_id: &str, result: DriveDownloadResult) {
        let mut state = match self.state.lock() {
            Ok(guard) => guard,
            Err(err) => {
                eprintln!("[drive-download] failed to lock state on success: {err}");
                return;
            }
        };

        let mut updated_task = None;
        if let Some(position) = state.active.iter().position(|t| t.item.id == item_id) {
            let mut task = state.active.remove(position);
            task.status = DownloadStatus::Completed;
            task.completed_at = Some(now_millis());
            task.saved_path = Some(result.saved_path.clone());
            task.size_label = Some(result.expected_size.unwrap_or(result.bytes_downloaded));
            task.bytes_downloaded = Some(result.bytes_downloaded);
            task.error_message = None;
            state.completed.insert(0, task.clone());
            updated_task = Some(task);
        }
        drop(state);
        if let Some(task) = updated_task {
            self.persist_task(&task);
        }
    }

    /// 下载异常时记录失败信息，保留最近失败历史。
    fn mark_failure(&self, item_id: &str, err_msg: String) {
        let mut state = match self.state.lock() {
            Ok(guard) => guard,
            Err(err) => {
                eprintln!("[drive-download] failed to lock state on failure: {err}");
                return;
            }
        };

        let mut updated_task = None;
        if let Some(position) = state.active.iter().position(|t| t.item.id == item_id) {
            let mut task = state.active.remove(position);
            task.status = DownloadStatus::Failed;
            task.completed_at = Some(now_millis());
            task.error_message = Some(err_msg.clone());
            state.failed.insert(0, task.clone());
            updated_task = Some(task);
        } else {
            // 如果任务不在 active 中，确保不会重复保留旧的失败记录。
            state.failed.retain(|task| task.item.id != item_id);
        }
        drop(state);
        if let Some(task) = updated_task {
            self.persist_task(&task);
        }
    }

    /// Rust 下载线程会通过该方法上报进度，随后同步数据库与内存状态。
    fn report_progress(&self, item_id: &str, bytes_downloaded: u64, expected_size: Option<u64>) {
        let mut state = match self.state.lock() {
            Ok(guard) => guard,
            Err(err) => {
                eprintln!("[drive-download] failed to lock state on progress: {err}");
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
            self.persist_task(&task);
        }
    }

    /// 删除任意状态的任务记录，常用于用户手动清理。
    fn remove_task(&self, item_id: &str) -> Result<DownloadQueueState, String> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| "download manager poisoned".to_string())?;
        state.active.retain(|task| task.item.id != item_id);
        state.completed.retain(|task| task.item.id != item_id);
        state.failed.retain(|task| task.item.id != item_id);
        let snapshot = (*state).clone();
        drop(state);
        self.remove_task_from_storage(item_id);
        Ok(snapshot.into())
    }

    /// 清空历史记录，保留进行中的任务。
    fn clear_history(&self) -> Result<DownloadQueueState, String> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| "download manager poisoned".to_string())?;
        state.completed.clear();
        state.failed.clear();
        let snapshot = (*state).clone();
        drop(state);
        self.clear_history_from_storage();
        Ok(snapshot.into())
    }

    /// 生成当前队列的不可变快照，避免 Flutter 持有 Mutex。
    fn snapshot(&self) -> DownloadQueueState {
        match self.state.lock() {
            Ok(guard) => (*guard).clone().into(),
            Err(_) => DownloadQueueState::default(),
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

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or_default()
}

fn record_from_task(task: &DownloadTask) -> DownloadTaskRecord {
    DownloadTaskRecord {
        item_id: task.item.id.clone(),
        item_name: task.item.name.clone(),
        size: opt_u64_to_i64(task.item.size),
        is_folder: task.item.is_folder,
        child_count: task.item.child_count,
        mime_type: task.item.mime_type.clone(),
        last_modified: task.item.last_modified.clone(),
        thumbnail_url: task.item.thumbnail_url.clone(),
        status: status_to_i64(&task.status),
        started_at: task.started_at,
        completed_at: task.completed_at,
        saved_path: task.saved_path.clone(),
        size_label: opt_u64_to_i64(task.size_label),
        bytes_downloaded: opt_u64_to_i64(task.bytes_downloaded),
        error_message: task.error_message.clone(),
        updated_at_millis: now_millis(),
    }
}

fn task_from_record(record: DownloadTaskRecord) -> DownloadTask {
    let DownloadTaskRecord {
        item_id,
        item_name,
        size,
        is_folder,
        child_count,
        mime_type,
        last_modified,
        thumbnail_url,
        status,
        started_at,
        completed_at,
        saved_path,
        size_label,
        bytes_downloaded,
        error_message,
        ..
    } = record;

    DownloadTask {
        item: DriveItemSummary {
            id: item_id,
            name: item_name,
            size: opt_i64_to_u64(size),
            is_folder,
            child_count,
            mime_type,
            last_modified,
            thumbnail_url,
        },
        status: status_from_i64(status),
        started_at,
        completed_at,
        saved_path,
        size_label: opt_i64_to_u64(size_label),
        bytes_downloaded: opt_i64_to_u64(bytes_downloaded),
        error_message,
    }
}

fn status_to_i64(status: &DownloadStatus) -> i64 {
    match status {
        DownloadStatus::InProgress => STATUS_IN_PROGRESS,
        DownloadStatus::Completed => STATUS_COMPLETED,
        DownloadStatus::Failed => STATUS_FAILED,
    }
}

fn status_from_i64(value: i64) -> DownloadStatus {
    match value {
        STATUS_COMPLETED => DownloadStatus::Completed,
        STATUS_FAILED => DownloadStatus::Failed,
        _ => DownloadStatus::InProgress,
    }
}

fn opt_u64_to_i64(value: Option<u64>) -> Option<i64> {
    value.and_then(|v| v.try_into().ok())
}

fn opt_i64_to_u64(value: Option<i64>) -> Option<u64> {
    value.and_then(|v| if v >= 0 { v.try_into().ok() } else { None })
}

#[flutter_rust_bridge::frb]
pub fn download_queue_state() -> DownloadQueueState {
    DownloadManager::shared().snapshot()
}

#[flutter_rust_bridge::frb]
pub fn enqueue_download_task(
    item: DriveItemSummary,
    target_dir: String,
    overwrite: bool,
) -> Result<DownloadQueueState, String> {
    DownloadManager::shared().enqueue_internal(item, target_dir, overwrite)
}

#[flutter_rust_bridge::frb]
pub fn remove_download_task(item_id: String) -> Result<DownloadQueueState, String> {
    DownloadManager::shared().remove_task(&item_id)
}

#[flutter_rust_bridge::frb]
pub fn clear_download_history() -> Result<DownloadQueueState, String> {
    DownloadManager::shared().clear_history()
}
