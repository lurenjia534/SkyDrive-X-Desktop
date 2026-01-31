mod client;
pub mod create_folder;
pub mod delete;
pub mod details;
pub mod download;
pub mod download_manager;
pub mod info;
pub mod list;
pub mod models;
pub mod move_item;
pub mod rename;
pub mod share;
pub mod upload;
pub mod upload_manager;

pub use create_folder::create_drive_folder;
pub use delete::delete_drive_item;
pub use details::get_drive_item_details;
pub use download::download_drive_item;
pub use download_manager::{
    clear_download_history, download_progress_stream, download_queue_state, enqueue_download_task,
    pause_download_task, remove_download_task, resume_download_task,
};
pub use info::get_drive_overview;
pub use list::list_drive_children;
pub use models::{
    DownloadQueueState, DownloadStatus, DownloadTask, DriveDownloadResult, DriveInfo,
    DriveItemDetails, DriveItemSummary, DriveOwner, DrivePage, DriveQuota, LinkScope, LinkType,
    ShareCapabilities, ShareLinkResult, UploadProgressUpdate, UploadQueueState, UploadStatus,
    UploadTask,
};
pub use move_item::move_drive_item;
pub use rename::rename_drive_item;
pub use share::{create_share_link, get_share_capabilities};
pub use upload::upload_small_file;
pub use upload_manager::{
    cancel_upload_task, clear_failed_upload_tasks, clear_upload_history, enqueue_upload_task,
    remove_upload_task, upload_progress_stream, upload_queue_state,
};

pub(crate) use client::current_access_token;

/// Graph v1 端点常量，集中声明方便今后切换区域或版本。
pub(crate) const GRAPH_BASE: &str = "https://graph.microsoft.com/v1.0";
