use super::{
    download::download_drive_item,
    models::{
        DownloadQueueState, DownloadStatus, DownloadTask, DriveDownloadResult, DriveItemSummary,
    },
};
use once_cell::sync::Lazy;
use std::{
    sync::{Arc, Mutex},
    thread,
    time::{SystemTime, UNIX_EPOCH},
};

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
        Self {
            state: Arc::new(Mutex::new(InnerState::default())),
        }
    }

    fn shared() -> Self {
        DOWNLOAD_MANAGER.clone()
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
            error_message: None,
        };
        state.active.push(task);
        drop(state);

        let manager = self.clone();
        let item_id = item.id.clone();
        thread::spawn(move || {
            let result = download_drive_item(item_id.clone(), target_dir, overwrite);
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

        if let Some(position) = state.active.iter().position(|t| t.item.id == item_id) {
            let mut task = state.active.remove(position);
            task.status = DownloadStatus::Completed;
            task.completed_at = Some(now_millis());
            task.saved_path = Some(result.saved_path.clone());
            task.size_label = Some(result.expected_size.unwrap_or(result.bytes_downloaded));
            task.error_message = None;
            state.completed.insert(0, task);
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

        if let Some(position) = state.active.iter().position(|t| t.item.id == item_id) {
            let mut task = state.active.remove(position);
            task.status = DownloadStatus::Failed;
            task.completed_at = Some(now_millis());
            task.error_message = Some(err_msg.clone());
            state.failed.insert(0, task);
        } else {
            // 如果任务不在 active 中，确保不会重复保留旧的失败记录。
            state.failed.retain(|task| task.item.id != item_id);
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
