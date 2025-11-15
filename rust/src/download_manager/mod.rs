pub mod core;
pub mod storage;

pub use core::{
    cancel_download_task, clear_download_history, clear_failed_download_tasks,
    download_queue_state, enqueue_download_task, get_download_directory, remove_download_task,
    set_download_directory, subscribe_progress, DownloadManager,
};
pub use storage::{DownloadStore, SqliteDownloadStore};
