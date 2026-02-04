use crate::frb_generated::StreamSink;
use crate::{
    api::drive::models::{
        BatchDownloadResult, DownloadProgressUpdate, DownloadQueueState, DriveItemSummary,
    },
    download_manager::{
        cancel_download_task as core_cancel, clear_download_history as core_clear_history,
        clear_failed_download_tasks as core_clear_failed, download_queue_state as core_queue_state,
        enqueue_download_task as core_enqueue,
        enqueue_download_tasks_batch as core_enqueue_batch, pause_download_task as core_pause,
        remove_download_task as core_remove, resume_download_task as core_resume,
        subscribe_progress as core_subscribe_progress,
    },
};
use std::thread;

#[flutter_rust_bridge::frb]
pub fn download_queue_state() -> DownloadQueueState {
    core_queue_state()
}

#[flutter_rust_bridge::frb]
pub fn enqueue_download_task(
    item: DriveItemSummary,
    target_dir: String,
    overwrite: bool,
) -> Result<DownloadQueueState, String> {
    core_enqueue(item, target_dir, overwrite)
}

#[flutter_rust_bridge::frb]
pub fn enqueue_download_tasks_batch(
    items: Vec<DriveItemSummary>,
    target_dir: String,
    overwrite: bool,
) -> Result<BatchDownloadResult, String> {
    core_enqueue_batch(items, target_dir, overwrite)
}

#[flutter_rust_bridge::frb]
pub fn remove_download_task(item_id: String) -> Result<DownloadQueueState, String> {
    core_remove(&item_id)
}

#[flutter_rust_bridge::frb]
pub fn cancel_download_task(item_id: String) -> Result<DownloadQueueState, String> {
    core_cancel(&item_id)
}

#[flutter_rust_bridge::frb]
pub fn pause_download_task(item_id: String) -> Result<DownloadQueueState, String> {
    core_pause(&item_id)
}

#[flutter_rust_bridge::frb]
pub fn resume_download_task(item_id: String, restart: bool) -> Result<DownloadQueueState, String> {
    core_resume(&item_id, restart)
}

#[flutter_rust_bridge::frb]
pub fn clear_failed_download_tasks() -> Result<DownloadQueueState, String> {
    core_clear_failed()
}

#[flutter_rust_bridge::frb]
pub fn clear_download_history() -> Result<DownloadQueueState, String> {
    core_clear_history()
}

#[flutter_rust_bridge::frb]
pub fn download_progress_stream(stream_sink: StreamSink<DownloadProgressUpdate>) {
    let rx = core_subscribe_progress();
    thread::spawn(move || {
        for update in rx.iter() {
            if stream_sink.add(update.clone()).is_err() {
                break;
            }
        }
    });
}
