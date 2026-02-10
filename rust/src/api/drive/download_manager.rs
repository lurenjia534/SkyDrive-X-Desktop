use crate::frb_generated::StreamSink;
use crate::{
    api::drive::models::{
        BatchDownloadResult, DownloadProgressUpdate, DownloadQueueState, DriveItemSummary,
    },
    download_manager::{
        cancel_download_task as core_cancel, clear_download_history as core_clear_history,
        clear_failed_download_tasks as core_clear_failed, download_queue_state as core_queue_state,
        enqueue_download_task as core_enqueue, enqueue_download_tasks_batch as core_enqueue_batch,
        pause_download_task as core_pause, remove_download_task as core_remove,
        resume_download_task as core_resume, subscribe_progress as core_subscribe_progress,
    },
};
use std::thread;

/// 获取当前下载队列快照（进行中/已完成/失败）。
#[flutter_rust_bridge::frb]
pub fn download_queue_state() -> DownloadQueueState {
    core_queue_state()
}

/// 入队单个下载任务并立即启动。
/// 若任务已存在于活动队列，返回错误。
#[flutter_rust_bridge::frb]
pub fn enqueue_download_task(
    item: DriveItemSummary,
    target_dir: String,
    overwrite: bool,
) -> Result<DownloadQueueState, String> {
    core_enqueue(item, target_dir, overwrite)
}

/// 批量入队下载任务。
/// 返回包含“跳过项/失败项”的批量结果，便于前端做部分成功提示。
#[flutter_rust_bridge::frb]
pub fn enqueue_download_tasks_batch(
    items: Vec<DriveItemSummary>,
    target_dir: String,
    overwrite: bool,
) -> Result<BatchDownloadResult, String> {
    core_enqueue_batch(items, target_dir, overwrite)
}

/// 从队列中移除指定任务。
#[flutter_rust_bridge::frb]
pub fn remove_download_task(item_id: String) -> Result<DownloadQueueState, String> {
    core_remove(&item_id)
}

/// 取消下载任务（语义上强于暂停）。
#[flutter_rust_bridge::frb]
pub fn cancel_download_task(item_id: String) -> Result<DownloadQueueState, String> {
    core_cancel(&item_id)
}

/// 暂停下载任务。
#[flutter_rust_bridge::frb]
pub fn pause_download_task(item_id: String) -> Result<DownloadQueueState, String> {
    core_pause(&item_id)
}

/// 恢复下载任务。
/// `restart=true` 时从头开始，否则尽量断点续传。
#[flutter_rust_bridge::frb]
pub fn resume_download_task(item_id: String, restart: bool) -> Result<DownloadQueueState, String> {
    core_resume(&item_id, restart)
}

/// 清理失败任务列表。
#[flutter_rust_bridge::frb]
pub fn clear_failed_download_tasks() -> Result<DownloadQueueState, String> {
    core_clear_failed()
}

/// 清理下载历史（保留当前活动任务）。
#[flutter_rust_bridge::frb]
pub fn clear_download_history() -> Result<DownloadQueueState, String> {
    core_clear_history()
}

/// 订阅下载进度流。
/// 内部通过线程桥接 Rust 事件到 FRB `StreamSink`。
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
