use crate::db;
use percent_encoding::{utf8_percent_encode, NON_ALPHANUMERIC};
use reqwest::blocking::Client;
use serde::Deserialize;
use std::time::Duration;

const GRAPH_BASE: &str = "https://graph.microsoft.com/v1.0";

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
pub fn list_drive_children(
    folder_id: Option<String>,
    folder_path: Option<String>,
    next_link: Option<String>,
) -> Result<DrivePage, String> {
    let access_token = current_access_token()?;
    let request_url = if let Some(link) = next_link {
        link
    } else if let Some(id) = folder_id {
        format!("{GRAPH_BASE}/me/drive/items/{id}/children{THUMBNAIL_QUERY}")
    } else {
        build_children_url(folder_path.as_deref())
    };

    fetch_drive_children(&request_url, &access_token)
}

fn current_access_token() -> Result<String, String> {
    let record = db::load_auth_record()?
        .ok_or_else(|| "no authentication state available; please sign in".to_string())?;
    Ok(record.access_token)
}

fn build_children_url(path: Option<&str>) -> String {
    match path {
        Some(raw) if !raw.trim().is_empty() => {
            let normalized = raw.trim_matches('/');
            if normalized.is_empty() {
                format!("{GRAPH_BASE}/me/drive/root/children{THUMBNAIL_QUERY}")
            } else {
                let encoded = normalized
                    .split('/')
                    .filter(|segment| !segment.is_empty())
                    .map(|segment| utf8_percent_encode(segment, NON_ALPHANUMERIC).to_string())
                    .collect::<Vec<_>>()
                    .join("/");
                format!("{GRAPH_BASE}/me/drive/root:/{encoded}:/children{THUMBNAIL_QUERY}")
            }
        }
        _ => format!("{GRAPH_BASE}/me/drive/root/children{THUMBNAIL_QUERY}"),
    }
}

const THUMBNAIL_QUERY: &str =
    "?$select=id,name,size,lastModifiedDateTime,folder,file&$expand=thumbnails($select=small,medium)";

fn fetch_drive_children(url: &str, access_token: &str) -> Result<DrivePage, String> {
    let client = Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|e| format!("failed to build HTTP client: {e}"))?;

    let response = client
        .get(url)
        .bearer_auth(access_token)
        .header("Accept", "application/json")
        .send()
        .map_err(|e| format!("failed to list drive items: {e}"))?;

    if response.status().as_u16() == 401 {
        return Err("access token rejected by Graph API; please sign in again".to_string());
    }

    if !response.status().is_success() {
        return Err(format!("graph api returned HTTP {}", response.status()));
    }

    let payload: DriveChildrenResponse = response
        .json()
        .map_err(|e| format!("failed to parse drive response: {e}"))?;

    let items = payload
        .value
        .into_iter()
        .map(DriveItemSummary::from)
        .collect();

    Ok(DrivePage {
        items,
        next_link: payload.next_link,
    })
}

impl From<DriveItemDto> for DriveItemSummary {
    fn from(value: DriveItemDto) -> Self {
        DriveItemSummary {
            id: value.id,
            name: value.name.unwrap_or_else(|| "(未命名)".to_string()),
            size: value.size,
            is_folder: value.folder.is_some(),
            child_count: value.folder.and_then(|f| f.child_count),
            mime_type: value.file.and_then(|f| f.mime_type),
            last_modified: value.last_modified_date_time,
            thumbnail_url: value
                .thumbnails
                .and_then(|sets| sets.into_iter().find_map(|set| set.best_url())),
        }
    }
}

#[derive(Debug, Deserialize)]
struct DriveChildrenResponse {
    value: Vec<DriveItemDto>,
    #[serde(rename = "@odata.nextLink")]
    next_link: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DriveItemDto {
    id: String,
    name: Option<String>,
    size: Option<u64>,
    #[serde(rename = "lastModifiedDateTime")]
    last_modified_date_time: Option<String>,
    folder: Option<DriveFolderFacet>,
    file: Option<DriveFileFacet>,
    thumbnails: Option<Vec<ThumbnailSetDto>>,
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

#[derive(Debug, Deserialize)]
struct ThumbnailSetDto {
    small: Option<ThumbnailDto>,
    medium: Option<ThumbnailDto>,
    large: Option<ThumbnailDto>,
}

#[derive(Debug, Deserialize)]
struct ThumbnailDto {
    url: Option<String>,
}

impl ThumbnailSetDto {
    fn best_url(self) -> Option<String> {
        self.small
            .and_then(|t| t.url)
            .or_else(|| self.medium.and_then(|t| t.url))
            .or_else(|| self.large.and_then(|t| t.url))
    }
}
