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

#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct DrivePage {
    pub items: Vec<DriveItemSummary>,
    pub next_link: Option<String>,
}

#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct DriveDownloadResult {
    pub file_name: String,
    pub saved_path: String,
    pub bytes_downloaded: u64,
    pub expected_size: Option<u64>,
}
