use crate::api::drive::models::{UploadStatus, UploadTask};
use crate::db::{
    clear_finished_upload_tasks, delete_upload_task, load_upload_tasks, upsert_upload_task,
    UploadTaskRecord,
};

/// 上传队列持久化接口，方便未来替换存储实现或编写单测。
pub trait UploadStore: Send + Sync {
    fn load(&self) -> Vec<UploadTask>;
    fn upsert(&self, task: &UploadTask);
    fn remove(&self, task_id: &str);
    fn clear_history(&self);
}

/// 默认的 SQLite 实现。
#[flutter_rust_bridge::frb(ignore)]
pub struct SqliteUploadStore {}

impl SqliteUploadStore {
    pub fn new() -> Self {
        SqliteUploadStore {}
    }
}

impl Default for SqliteUploadStore {
    fn default() -> Self {
        Self::new()
    }
}

impl UploadStore for SqliteUploadStore {
    fn load(&self) -> Vec<UploadTask> {
        load_upload_tasks()
            .map(|records| records.into_iter().map(task_from_record).collect())
            .unwrap_or_default()
    }

    fn upsert(&self, task: &UploadTask) {
        if let Err(err) = upsert_upload_task(&record_from_task(task)) {
            eprintln!(
                "[upload-store] failed to upsert task {}: {err}",
                task.task_id
            );
        }
    }

    fn remove(&self, task_id: &str) {
        if let Err(err) = delete_upload_task(task_id) {
            eprintln!("[upload-store] failed to delete task {task_id}: {err}");
        }
    }

    fn clear_history(&self) {
        if let Err(err) = clear_finished_upload_tasks(UploadStatus::InProgress as i64) {
            eprintln!("[upload-store] failed to clear upload history: {err}");
        }
    }
}

fn record_from_task(task: &UploadTask) -> UploadTaskRecord {
    UploadTaskRecord {
        task_id: task.task_id.clone(),
        file_name: task.file_name.clone(),
        local_path: task.local_path.clone(),
        size: task.size.and_then(|v| v.try_into().ok()),
        mime_type: task.mime_type.clone(),
        parent_id: task.parent_id.clone(),
        remote_id: task.remote_id.clone(),
        status: status_to_i64(&task.status),
        started_at: task.started_at,
        completed_at: task.completed_at,
        bytes_uploaded: task.bytes_uploaded.and_then(|v| v.try_into().ok()),
        error_message: task.error_message.clone(),
        session_url: task.session_url.clone(),
        updated_at_millis: crate::db::current_timestamp_millis(),
    }
}

fn task_from_record(record: UploadTaskRecord) -> UploadTask {
    UploadTask {
        task_id: record.task_id,
        file_name: record.file_name,
        local_path: record.local_path,
        size: record
            .size
            .and_then(|v| if v >= 0 { v.try_into().ok() } else { None }),
        mime_type: record.mime_type,
        parent_id: record.parent_id,
        remote_id: record.remote_id,
        status: status_from_i64(record.status),
        started_at: record.started_at,
        completed_at: record.completed_at,
        bytes_uploaded: record.bytes_uploaded.and_then(|v| {
            if v >= 0 {
                v.try_into().ok()
            } else {
                None
            }
        }),
        error_message: record.error_message,
        session_url: record.session_url,
    }
}

fn status_to_i64(status: &UploadStatus) -> i64 {
    match status {
        UploadStatus::InProgress => 0,
        UploadStatus::Completed => 1,
        UploadStatus::Failed => 2,
        UploadStatus::Cancelled => 3,
    }
}

fn status_from_i64(value: i64) -> UploadStatus {
    match value {
        1 => UploadStatus::Completed,
        2 => UploadStatus::Failed,
        3 => UploadStatus::Cancelled,
        _ => UploadStatus::InProgress,
    }
}
