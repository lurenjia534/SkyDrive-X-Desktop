use super::{
    client::{build_blocking_client, send_with_refresh},
    models::DriveItemSummary,
    GRAPH_BASE,
};
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// 重命名文件/文件夹（DriveItem.name）。
/// - 可传入 if_match 防止覆盖（412）。
#[flutter_rust_bridge::frb]
pub fn rename_drive_item(
    item_id: String,
    new_name: String,
    if_match: Option<String>,
) -> Result<DriveItemSummary, String> {
    if item_id.trim().is_empty() {
        return Err("drive item id is required".to_string());
    }
    if new_name.trim().is_empty() {
        return Err("new name cannot be empty".to_string());
    }

    let body = RenameRequest::new(new_name);
    let client = build_blocking_client(Duration::from_secs(30))?;
    let url = format!("{GRAPH_BASE}/me/drive/items/{item_id}");

    let response = send_with_refresh(|token| {
        let mut request = client
            .patch(&url)
            .bearer_auth(token)
            .header("Accept", "application/json")
            .json(&body);
        if let Some(tag) = if_match.as_deref() {
            request = request.header("If-Match", tag);
        }
        request
            .send()
            .map_err(|e| format!("failed to rename drive item: {e}"))
    })?;

    if response.status().as_u16() == 401 {
        return Err("access token rejected by Graph API; please sign in again".to_string());
    }
    if response.status().as_u16() == 404 {
        return Err("未找到指定的项目，可能已被移动或删除".to_string());
    }
    if response.status().as_u16() == 412 {
        return Err("If-Match 校验失败，项目已被其他操作修改".to_string());
    }
    if !response.status().is_success() {
        return Err(format!(
            "graph api returned HTTP {} while renaming item",
            response.status()
        ));
    }

    let payload: RenameResponse =
        response.json().map_err(|e| format!("failed to parse rename response: {e}"))?;

    Ok(DriveItemSummary {
        id: payload.id,
        name: payload.name.unwrap_or_else(|| "(未命名)".to_string()),
        size: payload.size,
        is_folder: payload.folder.is_some(),
        child_count: payload.folder.and_then(|f| f.child_count),
        mime_type: payload.file.and_then(|f| f.mime_type),
        last_modified: payload.last_modified_date_time,
        thumbnail_url: None,
    })
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct RenameRequest {
    name: String,
}

impl RenameRequest {
    fn new(name: String) -> Self {
        RenameRequest { name }
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RenameResponse {
    id: String,
    name: Option<String>,
    size: Option<u64>,
    #[serde(rename = "lastModifiedDateTime")]
    last_modified_date_time: Option<String>,
    folder: Option<DriveFolderFacet>,
    file: Option<DriveFileFacet>,
}

#[derive(Debug, Deserialize)]
struct DriveFolderFacet {
    #[serde(rename = "childCount")]
    child_count: Option<i64>,
}

#[derive(Debug, Deserialize)]
struct DriveFileFacet {
    #[serde(rename = "mimeType")]
    mime_type: Option<String>,
}
