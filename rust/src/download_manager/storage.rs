use crate::api::drive::models::{DownloadStatus, DownloadTask, DriveItemSummary};
use crate::db::{
    clear_finished_download_tasks, delete_download_task, load_download_tasks, upsert_download_task,
    DownloadTaskRecord,
};

/// 定义持久化接口，方便未来替换存储实现或编写单测。
pub trait DownloadStore: Send + Sync {
    fn load(&self) -> Vec<DownloadTask>;
    fn upsert(&self, task: &DownloadTask);
    fn remove(&self, item_id: &str);
    fn clear_history(&self);
}

/// 默认的 SQLite 实现：直接复用现有 `crate::db` 工具集。
#[flutter_rust_bridge::frb(ignore)]
pub struct SqliteDownloadStore {}

impl SqliteDownloadStore {
    pub fn new() -> Self {
        SqliteDownloadStore {}
    }
}

impl Default for SqliteDownloadStore {
    fn default() -> Self {
        Self::new()
    }
}

impl DownloadStore for SqliteDownloadStore {
    /// 从数据库载入所有任务，并映射回 Rust 结构。
    fn load(&self) -> Vec<DownloadTask> {
        load_download_tasks()
            .map(|records| records.into_iter().map(task_from_record).collect())
            .unwrap_or_default()
    }

    /// upsert 单条任务，避免 active/历史状态分散在多个表。
    fn upsert(&self, task: &DownloadTask) {
        if let Err(err) = upsert_download_task(&record_from_task(task)) {
            eprintln!(
                "[download-store] failed to upsert task {}: {err}",
                task.item.id
            );
        }
    }

    /// 删除任意状态的任务记录。
    fn remove(&self, item_id: &str) {
        if let Err(err) = delete_download_task(item_id) {
            eprintln!("[download-store] failed to delete task {item_id}: {err}");
        }
    }

    /// 清理历史记录，保留 active 船票给上层状态机使用。
    fn clear_history(&self) {
        if let Err(err) = clear_finished_download_tasks(DownloadStatus::InProgress as i64) {
            eprintln!("[download-store] failed to clear download history: {err}");
        }
    }
}

/// 将运行时任务转换成数据库记录；统一在此处理类型与符号转换。
fn record_from_task(task: &DownloadTask) -> DownloadTaskRecord {
    DownloadTaskRecord {
        item_id: task.item.id.clone(),
        item_name: task.item.name.clone(),
        size: task.item.size.and_then(|v| v.try_into().ok()),
        is_folder: task.item.is_folder,
        child_count: task.item.child_count,
        mime_type: task.item.mime_type.clone(),
        last_modified: task.item.last_modified.clone(),
        thumbnail_url: task.item.thumbnail_url.clone(),
        status: status_to_i64(&task.status),
        started_at: task.started_at,
        completed_at: task.completed_at,
        saved_path: task.saved_path.clone(),
        size_label: task.size_label.and_then(|v| v.try_into().ok()),
        bytes_downloaded: task.bytes_downloaded.and_then(|v| v.try_into().ok()),
        error_message: task.error_message.clone(),
        updated_at_millis: crate::db::current_timestamp_millis(),
    }
}

fn task_from_record(record: DownloadTaskRecord) -> DownloadTask {
    DownloadTask {
        item: DriveItemSummary {
            id: record.item_id,
            name: record.item_name,
            size: record
                .size
                .and_then(|v| if v >= 0 { v.try_into().ok() } else { None }),
            is_folder: record.is_folder,
            child_count: record.child_count,
            mime_type: record.mime_type,
            last_modified: record.last_modified,
            thumbnail_url: record.thumbnail_url,
        },
        status: status_from_i64(record.status),
        started_at: record.started_at,
        completed_at: record.completed_at,
        saved_path: record.saved_path,
        size_label: record
            .size_label
            .and_then(|v| if v >= 0 { v.try_into().ok() } else { None }),
        bytes_downloaded: record.bytes_downloaded.and_then(|v| {
            if v >= 0 {
                v.try_into().ok()
            } else {
                None
            }
        }),
        error_message: record.error_message,
    }
}

fn status_to_i64(status: &DownloadStatus) -> i64 {
    match status {
        DownloadStatus::InProgress => 0,
        DownloadStatus::Completed => 1,
        DownloadStatus::Failed => 2,
    }
}

fn status_from_i64(value: i64) -> DownloadStatus {
    match value {
        1 => DownloadStatus::Completed,
        2 => DownloadStatus::Failed,
        _ => DownloadStatus::InProgress,
    }
}
