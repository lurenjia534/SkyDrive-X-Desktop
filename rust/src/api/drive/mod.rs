mod client;
pub mod download;
pub mod download_manager;
pub mod list;
pub mod models;
pub mod upload;

pub use download::download_drive_item;
pub use download_manager::{
    clear_download_history, download_progress_stream, download_queue_state, enqueue_download_task,
    remove_download_task,
};
pub use list::list_drive_children;
pub use models::{
    DownloadQueueState, DownloadStatus, DownloadTask, DriveDownloadResult, DriveItemSummary,
    DrivePage,
};
pub use upload::upload_small_file;

/// Graph v1 端点常量，集中声明方便今后切换区域或版本。
pub(crate) const GRAPH_BASE: &str = "https://graph.microsoft.com/v1.0";
