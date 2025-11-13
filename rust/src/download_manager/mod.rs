pub mod core;
pub mod storage;

pub use core::{
    clear_download_history, download_queue_state, enqueue_download_task, remove_download_task,
    subscribe_progress, DownloadManager,
};
pub use storage::{DownloadStore, SqliteDownloadStore};
