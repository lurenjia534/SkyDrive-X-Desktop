mod client;
/// Drive API 聚合模块：
/// 对外组织 OneDrive 文件列表、搜索、下载/上传、分享、离线索引等能力。
pub mod create_folder;
pub mod delete;
pub mod details;
pub mod download;
pub mod download_manager;
pub mod gallery;
pub mod info;
pub mod list;
pub mod models;
pub mod move_item;
pub mod offline_index;
pub mod rename;
pub mod search;
pub mod share;
pub mod upload;
pub mod upload_manager;

// FRB 通过 re-export 导出统一的 crate::api::drive 命名空间接口。
pub use create_folder::create_drive_folder;
pub use delete::{delete_drive_item, delete_drive_items_batch};
pub use details::get_drive_item_details;
pub use download::download_drive_item;
pub use download_manager::{
    clear_download_history, download_progress_stream, download_queue_state, enqueue_download_task,
    enqueue_download_tasks_batch, pause_download_task, remove_download_task, resume_download_task,
};
pub use gallery::list_drive_gallery_items;
pub use info::get_drive_overview;
pub use list::list_drive_children;
pub use models::{
    BatchDownloadResult, DownloadQueueState, DownloadStatus, DownloadTask, DriveDownloadResult,
    DriveInfo, DriveItemDetails, DriveItemSummary, DriveOwner, DrivePage, DriveQuota, LinkScope,
    LinkType, OfflineIndexStatus, ShareCapabilities, ShareLinkResult, UploadProgressUpdate,
    UploadQueueState, UploadStatus, UploadTask,
};
pub use move_item::move_drive_item;
pub use offline_index::{get_offline_index_status, rebuild_offline_index, search_offline_index};
pub use rename::rename_drive_item;
pub use search::search_drive_items;
pub use share::{create_share_link, get_share_capabilities};
pub use upload::upload_small_file;
pub use upload_manager::{
    cancel_upload_task, clear_failed_upload_tasks, clear_upload_history, enqueue_upload_task,
    remove_upload_task, upload_progress_stream, upload_queue_state,
};

pub(crate) use client::current_access_token;

/// Graph v1 端点常量，集中声明方便今后切换区域或版本。
pub(crate) const GRAPH_BASE: &str = "https://graph.microsoft.com/v1.0";
