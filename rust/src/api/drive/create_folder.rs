use super::{
    client::{build_blocking_client, send_with_refresh},
    models::DriveItemSummary,
    GRAPH_BASE,
};
use percent_encoding::{utf8_percent_encode, NON_ALPHANUMERIC};
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// 在指定目录下创建文件夹。
#[flutter_rust_bridge::frb]
pub fn create_drive_folder(
    name: String,
    parent_id: Option<String>,
    parent_path: Option<String>,
    conflict_behavior: Option<String>,
) -> Result<DriveItemSummary, String> {
    let trimmed_name = name.trim();
    if trimmed_name.is_empty() {
        return Err("folder name is required".to_string());
    }
    if parent_id
        .as_ref()
        .map(|s| s.trim().is_empty())
        .unwrap_or(false)
    {
        return Err("parent id cannot be empty string".to_string());
    }
    if parent_path
        .as_ref()
        .map(|s| s.trim().is_empty())
        .unwrap_or(false)
    {
        return Err("parent path cannot be empty string".to_string());
    }

    let conflict = match conflict_behavior
        .as_deref()
        .unwrap_or("rename")
        .to_lowercase()
        .as_str()
    {
        "rename" => "rename",
        "fail" => "fail",
        "replace" => "replace",
        _ => {
            return Err("invalid conflict behavior (expected rename, fail, or replace)".to_string())
        }
    };

    let client = build_blocking_client(Duration::from_secs(30))?;
    let url = if let Some(id) = parent_id {
        format!("{GRAPH_BASE}/me/drive/items/{id}/children")
    } else {
        build_children_url(parent_path.as_deref())
    };

    let body = CreateFolderRequest::new(trimmed_name.to_string(), conflict);
    let response = send_with_refresh(|token| {
        client
            .post(&url)
            .bearer_auth(token)
            .header("Accept", "application/json")
            .json(&body)
            .send()
            .map_err(|e| format!("failed to create folder: {e}"))
    })?;

    if response.status().as_u16() == 401 {
        return Err("access token rejected by Graph API; please sign in again".to_string());
    }
    if response.status().as_u16() == 404 {
        return Err("未找到指定的父目录，可能已被移动或删除".to_string());
    }
    if response.status().as_u16() == 409 {
        return Err("同名文件夹已存在".to_string());
    }
    if !response.status().is_success() {
        return Err(format!(
            "graph api returned HTTP {} while creating folder",
            response.status()
        ));
    }

    let payload: CreateFolderResponse = response
        .json()
        .map_err(|e| format!("failed to parse create folder response: {e}"))?;

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

/// 根据路径构造 `/root:/path:/children` URL。
fn build_children_url(path: Option<&str>) -> String {
    match path {
        Some(raw) if !raw.trim().is_empty() => {
            let normalized = raw.trim_matches('/');
            if normalized.is_empty() {
                format!("{GRAPH_BASE}/me/drive/root/children")
            } else {
                let encoded = normalized
                    .split('/')
                    .filter(|segment| !segment.is_empty())
                    .map(|segment| utf8_percent_encode(segment, NON_ALPHANUMERIC).to_string())
                    .collect::<Vec<_>>()
                    .join("/");
                format!("{GRAPH_BASE}/me/drive/root:/{encoded}:/children")
            }
        }
        _ => format!("{GRAPH_BASE}/me/drive/root/children"),
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CreateFolderRequest {
    name: String,
    folder: FolderFacet,
    #[serde(rename = "@microsoft.graph.conflictBehavior")]
    conflict_behavior: String,
}

impl CreateFolderRequest {
    fn new(name: String, conflict_behavior: &str) -> Self {
        Self {
            name,
            folder: FolderFacet {},
            conflict_behavior: conflict_behavior.to_string(),
        }
    }
}

#[derive(Debug, Serialize)]
struct FolderFacet {}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CreateFolderResponse {
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
