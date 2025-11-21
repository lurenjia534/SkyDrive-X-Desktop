use super::{
    client::{build_blocking_client, current_access_token},
    models::DriveItemSummary,
    GRAPH_BASE,
};
use percent_encoding::{utf8_percent_encode, NON_ALPHANUMERIC};
use serde::Deserialize;
use std::time::Duration;

/// Graph 简易上传的官方上限（单请求），超出需走分片上传。
const SIMPLE_UPLOAD_MAX_BYTES: usize = 250 * 1024 * 1024;

/// 上传小文件（推荐 10MB 内，硬上限 250MB），存放到指定文件夹。
/// - 当 overwrite=true 时，如果存在同名文件，将直接覆盖。
/// - 当 overwrite=false 时，使用 Graph 的 rename 行为避免冲突。
/// - parent_id 为空时默认上传到根目录。
#[flutter_rust_bridge::frb]
pub fn upload_small_file(
    parent_id: Option<String>,
    file_name: String,
    content: Vec<u8>,
    overwrite: bool,
) -> Result<DriveItemSummary, String> {
    if file_name.trim().is_empty() {
        return Err("file name cannot be empty".to_string());
    }
    if content.len() > SIMPLE_UPLOAD_MAX_BYTES {
        return Err("file too large for simple upload; please use chunked upload".to_string());
    }

    let access_token = current_access_token()?;
    let client = build_blocking_client(Duration::from_secs(120))?;

    let encoded_name = utf8_percent_encode(file_name.trim(), NON_ALPHANUMERIC).to_string();
    let encoded_parent = parent_id
        .map(|id| id.trim().to_string())
        .filter(|id| !id.is_empty());

    let conflict = if overwrite { "replace" } else { "rename" };
    let url = if let Some(id) = encoded_parent {
        format!(
            "{GRAPH_BASE}/me/drive/items/{id}:/{encoded_name}:/content?@microsoft.graph.conflictBehavior={conflict}"
        )
    } else {
        format!(
            "{GRAPH_BASE}/me/drive/root:/{encoded_name}:/content?@microsoft.graph.conflictBehavior={conflict}"
        )
    };

    let response = client
        .put(url)
        .bearer_auth(access_token)
        .header("Content-Type", "application/octet-stream")
        .body(content)
        .send()
        .map_err(|e| format!("failed to upload file: {e}"))?;

    if response.status().as_u16() == 401 {
        return Err("access token rejected by Graph API; please sign in again".to_string());
    }

    if !response.status().is_success() {
        return Err(format!(
            "graph api returned HTTP {} while uploading",
            response.status()
        ));
    }

    let dto: DriveItemUploadResponse = response
        .json()
        .map_err(|e| format!("failed to parse upload response: {e}"))?;

    Ok(dto.into())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DriveItemUploadResponse {
    id: String,
    name: Option<String>,
    size: Option<u64>,
    #[serde(rename = "lastModifiedDateTime")]
    last_modified_date_time: Option<String>,
    file: Option<UploadFileFacet>,
}

#[derive(Debug, Deserialize)]
struct UploadFileFacet {
    #[serde(rename = "mimeType")]
    mime_type: Option<String>,
}

impl From<DriveItemUploadResponse> for DriveItemSummary {
    fn from(value: DriveItemUploadResponse) -> Self {
        DriveItemSummary {
            id: value.id,
            name: value.name.unwrap_or_else(|| "(未命名)".to_string()),
            size: value.size,
            is_folder: false,
            child_count: None,
            mime_type: value.file.and_then(|f| f.mime_type),
            last_modified: value.last_modified_date_time,
            thumbnail_url: None,
        }
    }
}
