use crate::db;
use percent_encoding::{utf8_percent_encode, NON_ALPHANUMERIC};
use reqwest::{blocking::Client, redirect::Policy};
use serde::Deserialize;
use std::{
    fs::{self, File},
    io::{self, BufWriter, Write},
    path::{Path, PathBuf},
    time::Duration,
};

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
#[derive(Clone, Debug)]
pub struct DriveDownloadResult {
    pub file_name: String,
    pub saved_path: String,
    pub bytes_downloaded: u64,
    pub expected_size: Option<u64>,
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

#[flutter_rust_bridge::frb]
pub fn download_drive_item(
    item_id: String,
    target_dir: String,
    overwrite: bool,
) -> Result<DriveDownloadResult, String> {
    if item_id.trim().is_empty() {
        return Err("drive item id is required".to_string());
    }
    if target_dir.trim().is_empty() {
        return Err("target directory is required".to_string());
    }

    let access_token = current_access_token()?;
    eprintln!("[drive-download] fetching metadata for item {}", item_id);
    let metadata = fetch_download_metadata(&item_id, &access_token)?;

    if metadata.file.is_none() {
        eprintln!(
            "[drive-download] item {} has no file facet (name={:?})",
            item_id, metadata.name
        );
        return Err("选中的项目不是可下载的文件".to_string());
    }

    let (download_endpoint, bearer_token) = match metadata.download_url.as_ref() {
        Some(url) => {
            eprintln!(
                "[drive-download] using pre-authenticated download url for {}",
                item_id
            );
            (url.clone(), None)
        }
        None => {
            eprintln!(
                "[drive-download] missing downloadUrl, fallback to /content for {}",
                item_id
            );
            let content_url = format!("{GRAPH_BASE}/me/drive/items/{item_id}/content");
            (content_url, Some(access_token.as_str()))
        }
    };

    let file_name = metadata
        .name
        .as_deref()
        .map(sanitize_file_name)
        .unwrap_or_else(|| "download.bin".to_string());

    let destination = prepare_destination(&target_dir, &file_name, overwrite)?;
    let bytes_downloaded = stream_download(&download_endpoint, bearer_token, &destination)?;
    eprintln!(
        "[drive-download] saved {} bytes to {}",
        bytes_downloaded,
        destination.to_string_lossy()
    );
    let saved_path = destination
        .canonicalize()
        .unwrap_or(destination.clone())
        .to_string_lossy()
        .into_owned();

    Ok(DriveDownloadResult {
        file_name,
        saved_path,
        bytes_downloaded,
        expected_size: metadata.size,
    })
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
    let client = build_blocking_client(Duration::from_secs(30))?;

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

fn build_blocking_client(timeout: Duration) -> Result<Client, String> {
    Client::builder()
        .timeout(timeout)
        .redirect(Policy::limited(10))
        .build()
        .map_err(|e| format!("failed to build HTTP client: {e}"))
}

fn fetch_download_metadata(
    item_id: &str,
    access_token: &str,
) -> Result<DriveItemDownloadDto, String> {
    let client = build_blocking_client(Duration::from_secs(30))?;
    let url = format!(
        "{GRAPH_BASE}/me/drive/items/{item_id}?$select=name,size,file,@microsoft.graph.downloadUrl"
    );
    let response = client
        .get(url)
        .bearer_auth(access_token)
        .header("Accept", "application/json")
        .send()
        .map_err(|e| format!("failed to fetch download metadata: {e}"))?;

    if response.status().as_u16() == 401 {
        return Err("access token rejected by Graph API; please sign in again".to_string());
    }
    if response.status().as_u16() == 404 {
        return Err("找不到指定的文件，可能已经被移动或删除".to_string());
    }
    if !response.status().is_success() {
        return Err(format!(
            "graph api returned HTTP {} while fetching download info",
            response.status()
        ));
    }

    response
        .json::<DriveItemDownloadDto>()
        .map_err(|e| format!("failed to parse download metadata: {e}"))
}

fn sanitize_file_name(raw: &str) -> String {
    let trimmed = raw.trim();
    let fallback = "download.bin";
    let candidate = if trimmed.is_empty() {
        fallback
    } else {
        trimmed
    };

    let sanitized: String = candidate
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            _ => c,
        })
        .collect();

    let final_name = sanitized.trim();
    if final_name.is_empty() || final_name == "." || final_name == ".." {
        fallback.to_string()
    } else {
        final_name.to_string()
    }
}

fn prepare_destination(
    target_dir: &str,
    file_name: &str,
    overwrite: bool,
) -> Result<PathBuf, String> {
    let dir_path = Path::new(target_dir);
    fs::create_dir_all(dir_path)
        .map_err(|e| format!("无法创建下载目录 {}: {e}", dir_path.to_string_lossy()))?;

    let destination = dir_path.join(file_name);
    if destination.exists() && !overwrite {
        return Err(format!(
            "文件已存在：{}（如需覆盖请设置 overwrite=true）",
            destination.to_string_lossy()
        ));
    }

    Ok(destination)
}

fn stream_download(
    download_url: &str,
    bearer_token: Option<&str>,
    destination: &Path,
) -> Result<u64, String> {
    let client = build_blocking_client(Duration::from_secs(600))?;
    let mut request = client.get(download_url);
    if let Some(token) = bearer_token {
        request = request.bearer_auth(token);
    }
    let mut response = request
        .send()
        .map_err(|e| format!("failed to download file: {e}"))?;

    if !response.status().is_success() {
        return Err(format!(
            "download endpoint returned HTTP {}",
            response.status()
        ));
    }

    let file = File::create(destination).map_err(|e| {
        format!(
            "failed to create destination file {}: {e}",
            destination.to_string_lossy()
        )
    })?;
    let mut writer = BufWriter::new(file);

    let bytes_copied =
        io::copy(&mut response, &mut writer).map_err(|e| format!("failed to write file: {e}"))?;
    writer
        .flush()
        .map_err(|e| format!("failed to flush file: {e}"))?;

    Ok(bytes_copied)
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
#[serde(rename_all = "camelCase")]
struct DriveItemDownloadDto {
    name: Option<String>,
    size: Option<u64>,
    file: Option<DriveFileFacet>,
    #[serde(rename = "@microsoft.graph.downloadUrl")]
    download_url: Option<String>,
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
