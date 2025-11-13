use super::{
    client::{build_blocking_client, current_access_token},
    models::DriveDownloadResult,
    GRAPH_BASE,
};
use serde::Deserialize;
use std::{
    fs::{self, File},
    io::{BufWriter, Read, Write},
    path::{Path, PathBuf},
    time::Duration,
};

type ProgressCallback = Box<dyn FnMut(u64, Option<u64>) + Send>;

/// 下载指定 drive item（仅文件），保存到 target_dir。
/// - 优先使用 Graph 返回的 downloadUrl（免鉴权）。
/// - 若 downloadUrl 缺失，回退到 `/content` 并携带 token。
#[flutter_rust_bridge::frb]
pub fn download_drive_item(
    item_id: String,
    target_dir: String,
    overwrite: bool,
) -> Result<DriveDownloadResult, String> {
    download_drive_item_internal(item_id, target_dir, overwrite, None)
}

pub(crate) fn download_drive_item_with_progress(
    item_id: String,
    target_dir: String,
    overwrite: bool,
    progress: Option<ProgressCallback>,
) -> Result<DriveDownloadResult, String> {
    download_drive_item_internal(item_id, target_dir, overwrite, progress)
}

fn download_drive_item_internal(
    item_id: String,
    target_dir: String,
    overwrite: bool,
    mut progress: Option<ProgressCallback>,
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
    if let Some(cb) = progress.as_mut() {
        cb(0, metadata.size);
    }
    let mut progress_ref = progress
        .as_mut()
        .map(|cb| cb.as_mut() as &mut (dyn FnMut(u64, Option<u64>) + Send));
    let bytes_downloaded = stream_download(
        &download_endpoint,
        bearer_token,
        &destination,
        metadata.size,
        progress_ref.as_deref_mut(),
    )?;
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

fn fetch_download_metadata(
    item_id: &str,
    access_token: &str,
) -> Result<DriveItemDownloadDto, String> {
    // 单次请求只关心必要字段，避免传输冗余信息。
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

/// 对 Graph 返回的文件名进行清洗，兼容不同桌面平台的非法字符。
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

/// 创建下载目录并返回目标文件路径，避免覆盖已存在文件（除非设置 overwrite）。
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

/// 实际执行 HTTP 下载并流式写入磁盘，必要时附带 Bearer token。
fn stream_download(
    download_url: &str,
    bearer_token: Option<&str>,
    destination: &Path,
    total_size: Option<u64>,
    mut progress: Option<&mut (dyn FnMut(u64, Option<u64>) + Send)>,
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

    let mut downloaded: u64 = 0;
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let read_bytes = response
            .read(&mut buffer)
            .map_err(|e| format!("failed to read response body: {e}"))?;
        if read_bytes == 0 {
            break;
        }
        writer
            .write_all(&buffer[..read_bytes])
            .map_err(|e| format!("failed to write file: {e}"))?;
        downloaded += read_bytes as u64;
        if let Some(ref mut cb) = progress {
            cb(downloaded, total_size);
        }
    }
    writer
        .flush()
        .map_err(|e| format!("failed to flush file: {e}"))?;

    Ok(downloaded)
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

#[allow(dead_code)] // metadata 中可能暂时只读取 mime_type，因此关闭未使用告警
#[derive(Debug, Deserialize)]
struct DriveFileFacet {
    #[serde(rename = "mimeType")]
    mime_type: Option<String>,
}
