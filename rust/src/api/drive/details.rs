use super::{
    client::{build_blocking_client, current_access_token},
    models::DriveItemDetails,
    GRAPH_BASE,
};
use serde::Deserialize;
use std::time::Duration;

/// 获取单个 drive item 的完整属性，用于属性面板显示。
#[flutter_rust_bridge::frb]
pub fn get_drive_item_details(item_id: String) -> Result<DriveItemDetails, String> {
    if item_id.trim().is_empty() {
        return Err("drive item id is required".to_string());
    }
    let access_token = current_access_token()?;
    let client = build_blocking_client(Duration::from_secs(30))?;

    // 保留常用字段与关键 facet；如需更多关系（children/versions），另行调用。
    let url = format!("{GRAPH_BASE}/me/drive/items/{item_id}?$select=id,name,size,createdDateTime,lastModifiedDateTime,webUrl,eTag,cTag,file,folder,fileSystemInfo,parentReference,@microsoft.graph.downloadUrl");
    let response = client
        .get(url)
        .bearer_auth(&access_token)
        .header("Accept", "application/json")
        .send()
        .map_err(|e| format!("failed to fetch drive item details: {e}"))?;

    if response.status().as_u16() == 401 {
        return Err("access token rejected by Graph API; please sign in again".to_string());
    }
    if response.status().as_u16() == 404 {
        return Err("未找到指定的项目，可能已被移动或删除".to_string());
    }
    if !response.status().is_success() {
        return Err(format!(
            "graph api returned HTTP {} while fetching item details",
            response.status()
        ));
    }

    let payload: DriveItemDetailsDto = response
        .json()
        .map_err(|e| format!("failed to parse drive item details: {e}"))?;

    Ok(payload.into())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DriveItemDetailsDto {
    id: String,
    name: Option<String>,
    size: Option<u64>,
    #[serde(rename = "createdDateTime")]
    created_date_time: Option<String>,
    #[serde(rename = "lastModifiedDateTime")]
    last_modified_date_time: Option<String>,
    #[serde(rename = "eTag")]
    e_tag: Option<String>,
    #[serde(rename = "cTag")]
    c_tag: Option<String>,
    web_url: Option<String>,
    #[serde(rename = "@microsoft.graph.downloadUrl")]
    download_url: Option<String>,
    file: Option<DriveFileFacetDto>,
    folder: Option<DriveFolderFacetDto>,
    file_system_info: Option<FileSystemInfoDto>,
    parent_reference: Option<ParentReferenceDto>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DriveFileFacetDto {
    #[serde(rename = "mimeType")]
    mime_type: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DriveFolderFacetDto {
    #[serde(rename = "childCount")]
    child_count: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct FileSystemInfoDto {
    #[serde(rename = "createdDateTime")]
    created_date_time: Option<String>,
    #[serde(rename = "lastModifiedDateTime")]
    last_modified_date_time: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ParentReferenceDto {
    path: Option<String>,
}

impl From<DriveItemDetailsDto> for DriveItemDetails {
    fn from(value: DriveItemDetailsDto) -> Self {
        DriveItemDetails {
            id: value.id,
            name: value.name.unwrap_or_else(|| "(未命名)".to_string()),
            size: value.size,
            mime_type: value.file.and_then(|f| f.mime_type),
            is_folder: value.folder.is_some(),
            child_count: value.folder.and_then(|f| f.child_count),
            created_at: value.created_date_time,
            last_modified_at: value.last_modified_date_time,
            file_system_created_at: value
                .file_system_info
                .as_ref()
                .and_then(|f| f.created_date_time.clone()),
            file_system_modified_at: value
                .file_system_info
                .as_ref()
                .and_then(|f| f.last_modified_date_time.clone()),
            web_url: value.web_url,
            download_url: value.download_url,
            etag: value.e_tag,
            ctag: value.c_tag,
            parent_path: value.parent_reference.and_then(|p| p.path),
        }
    }
}
