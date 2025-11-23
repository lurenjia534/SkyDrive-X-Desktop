use crate::api::drive::models::{UploadProgressUpdate, UploadQueueState};
use crate::frb_generated::StreamSink;
use crate::upload_manager::UploadManager;
use flutter_rust_bridge::frb;

#[frb]
pub fn upload_queue_state() -> UploadQueueState {
    UploadManager::shared().snapshot()
}

#[frb]
pub fn enqueue_upload_task(
    parent_id: Option<String>,
    file_name: String,
    local_path: String,
    content: Vec<u8>,
    overwrite: bool,
) -> Result<UploadQueueState, String> {
    UploadManager::shared().enqueue_small_file(parent_id, file_name, local_path, content, overwrite)
}

#[frb]
pub fn enqueue_large_upload_task(
    parent_id: Option<String>,
    file_name: String,
    local_path: String,
    overwrite: bool,
) -> Result<UploadQueueState, String> {
    UploadManager::shared().enqueue_large_file(parent_id, file_name, local_path, overwrite)
}

#[frb]
pub fn remove_upload_task(task_id: String) -> Result<UploadQueueState, String> {
    UploadManager::shared().remove(&task_id)
}

#[frb]
pub fn cancel_upload_task(task_id: String) -> Result<UploadQueueState, String> {
    UploadManager::shared().cancel(&task_id)
}

#[frb]
pub fn clear_failed_upload_tasks() -> Result<UploadQueueState, String> {
    UploadManager::shared().clear_failed_tasks()
}

#[frb]
pub fn clear_upload_history() -> Result<UploadQueueState, String> {
    UploadManager::shared().clear_history()
}

#[frb]
pub fn upload_progress_stream(stream_sink: StreamSink<UploadProgressUpdate>) {
    let rx = UploadManager::shared().subscribe_progress();
    std::thread::spawn(move || {
        for update in rx {
            if stream_sink.add(update.clone()).is_err() {
                break;
            }
        }
    });
}
