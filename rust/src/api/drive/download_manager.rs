use crate::frb_generated::StreamSink;
use crate::{
    api::drive::models::{DownloadProgressUpdate, DownloadQueueState, DriveItemSummary},
    download_manager::{
        clear_download_history as core_clear_history, download_queue_state as core_queue_state,
        enqueue_download_task as core_enqueue, remove_download_task as core_remove,
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
pub fn remove_download_task(item_id: String) -> Result<DownloadQueueState, String> {
    core_remove(&item_id)
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
