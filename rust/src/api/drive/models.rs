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
