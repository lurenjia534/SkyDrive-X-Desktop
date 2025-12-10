use super::{
    client::{build_blocking_client, current_access_token},
    models::DriveItemSummary,
    GRAPH_BASE,
};
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// 将文件/文件夹移动到同一 Drive 下的新父目录，并可选重命名。
/// - 只支持同一 Drive 内移动，Graph 官方不支持跨 Drive。
/// - 可传入 if_match 防止覆盖（412）。
#[flutter_rust_bridge::frb]
pub fn move_drive_item(
    item_id: String,
    new_parent_id: Option<String>,
    new_name: Option<String>,
    if_match: Option<String>,
) -> Result<DriveItemSummary, String> {
    if item_id.trim().is_empty() {
        return Err("drive item id is required".to_string());
    }
    if new_parent_id.as_ref().map(|s| s.trim().is_empty()).unwrap_or(false) {
        return Err("new parent id cannot be empty string".to_string());
    }
    if new_name.as_ref().map(|s| s.trim().is_empty()).unwrap_or(false) {
        return Err("new name cannot be empty string".to_string());
    }

    let body = MoveRequest::new(new_parent_id, new_name);
    let access_token = current_access_token()?;
    let client = build_blocking_client(Duration::from_secs(30))?;
    let url = format!("{GRAPH_BASE}/me/drive/items/{item_id}");

    let mut request = client
        .patch(url)
        .bearer_auth(&access_token)
        .header("Accept", "application/json")
        .json(&body);
    if let Some(tag) = if_match {
        request = request.header("If-Match", tag);
    }

    let response = request
        .send()
        .map_err(|e| format!("failed to move drive item: {e}"))?;

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
            "graph api returned HTTP {} while moving item",
            response.status()
        ));
    }

    let payload: MoveResponse =
        response.json().map_err(|e| format!("failed to parse move response: {e}"))?;

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
struct MoveRequest {
    #[serde(skip_serializing_if = "Option::is_none")]
    parent_reference: Option<ParentRefDto>,
    #[serde(skip_serializing_if = "Option::is_none")]
    name: Option<String>,
}

impl MoveRequest {
    fn new(parent_id: Option<String>, name: Option<String>) -> Self {
        MoveRequest {
            parent_reference: parent_id.map(|id| ParentRefDto { id }),
            name,
        }
    }
}

#[derive(Debug, Serialize)]
struct ParentRefDto {
    id: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MoveResponse {
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
