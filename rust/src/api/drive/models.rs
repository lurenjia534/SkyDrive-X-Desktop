/// 与 Flutter 侧共享的 OneDrive 文件/文件夹摘要结构。
/// 字段命名保持与 Graph API 对齐，避免额外映射。
#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct DriveItemSummary {
    pub id: String,
    pub name: String,
    pub size: Option<u64>,
    pub is_folder: bool,
    pub child_count: Option<i64>,
    pub mime_type: Option<String>,
    pub last_modified: Option<String>,
    pub thumbnail_url: Option<String>,
}

/// 列表接口的分页结果，包含子项与 nextLink。
#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct DrivePage {
    pub items: Vec<DriveItemSummary>,
    pub next_link: Option<String>,
}

/// 下载完成后的结果描述，便于前端提示保存路径与大小。
#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct DriveDownloadResult {
    pub file_name: String,
    pub saved_path: String,
    pub bytes_downloaded: u64,
    pub expected_size: Option<u64>,
}

/// 下载任务状态，迁移至 Rust 端统一管理。
#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub enum DownloadStatus {
    InProgress,
    Completed,
    Failed,
}

/// 上传任务状态。
#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub enum UploadStatus {
    InProgress,
    Completed,
    Failed,
    Cancelled,
}

/// 单条下载任务详情，供 Flutter 展示进度与历史。
#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct DownloadTask {
    pub item: DriveItemSummary,
    pub status: DownloadStatus,
    pub started_at: i64,
    pub completed_at: Option<i64>,
    pub saved_path: Option<String>,
    pub size_label: Option<u64>,
    pub bytes_downloaded: Option<u64>,
    pub error_message: Option<String>,
}

/// 单条上传任务详情。
#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct UploadTask {
    pub task_id: String,
    pub file_name: String,
    pub local_path: String,
    pub size: Option<u64>,
    pub mime_type: Option<String>,
    pub parent_id: Option<String>,
    pub remote_id: Option<String>,
    pub status: UploadStatus,
    pub started_at: i64,
    pub completed_at: Option<i64>,
    pub bytes_uploaded: Option<u64>,
    pub error_message: Option<String>,
    pub session_url: Option<String>,
}

/// 下载队列状态，包含进行中、已完成与失败任务列表。
#[flutter_rust_bridge::frb]
#[derive(Clone, Debug, Default)]
pub struct DownloadQueueState {
    pub active: Vec<DownloadTask>,
    pub completed: Vec<DownloadTask>,
    pub failed: Vec<DownloadTask>,
}

/// 上传队列状态。
#[flutter_rust_bridge::frb]
#[derive(Clone, Debug, Default)]
pub struct UploadQueueState {
    pub active: Vec<UploadTask>,
    pub completed: Vec<UploadTask>,
    pub failed: Vec<UploadTask>,
}

/// 下载进度事件，通过 StreamSink 推送给 Flutter，供 UI 实时刷新进度与速度。
#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct DownloadProgressUpdate {
    pub item_id: String,
    pub bytes_downloaded: u64,
    pub expected_size: Option<u64>,
    pub speed_bps: Option<f64>,
    pub timestamp_millis: i64,
}

/// 上传进度事件，用于前端展示实时上传状态。
#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct UploadProgressUpdate {
    pub task_id: String,
    pub bytes_uploaded: u64,
    pub expected_size: Option<u64>,
    pub speed_bps: Option<f64>,
    pub timestamp_millis: i64,
}

/// OneDrive 概览信息（配额、类型、所有者）。
#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct DriveInfo {
    pub id: Option<String>,
    pub drive_type: Option<String>,
    pub owner: Option<DriveOwner>,
    pub quota: Option<DriveQuota>,
}

/// OneDrive 所有者基本信息。
#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct DriveOwner {
    pub display_name: Option<String>,
    pub user_principal_name: Option<String>,
    pub id: Option<String>,
}

/// OneDrive 配额字段，直接保留 Graph 原始值。
#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct DriveQuota {
    pub total: Option<u64>,
    pub used: Option<u64>,
    pub remaining: Option<u64>,
    pub deleted: Option<u64>,
    pub state: Option<String>,
}

/// drive item 详情，供属性面板使用。
#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct DriveItemDetails {
    pub id: String,
    pub name: String,
    pub size: Option<u64>,
    pub mime_type: Option<String>,
    pub is_folder: bool,
    pub child_count: Option<i64>,
    pub created_at: Option<String>,
    pub last_modified_at: Option<String>,
    pub file_system_created_at: Option<String>,
    pub file_system_modified_at: Option<String>,
    pub web_url: Option<String>,
    pub download_url: Option<String>,
    pub etag: Option<String>,
    pub ctag: Option<String>,
    pub parent_path: Option<String>,
}
