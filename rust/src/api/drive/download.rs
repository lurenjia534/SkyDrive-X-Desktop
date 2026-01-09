use super::{
    client::{build_blocking_client, current_access_token, refresh_access_token, send_with_refresh},
    models::DriveDownloadResult,
    GRAPH_BASE,
};
use serde::Deserialize;
use std::{
    cell::RefCell,
    fs::{self, OpenOptions},
    io::{BufWriter, Read, Seek, SeekFrom, Write},
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicU8, Ordering},
        Arc,
    },
    time::Duration,
};

/// 回调函数签名：传入当前已下载字节数以及 Graph 预估的总大小。
/// - `Option<u64>` 用于处理 Graph 未返回 size 的场景。
type ProgressCallback = Box<dyn FnMut(u64, Option<u64>) + Send>;

pub(crate) const CONTROL_FLAG_NONE: u8 = 0;
pub(crate) const CONTROL_FLAG_PAUSE: u8 = 1;
pub(crate) const CONTROL_FLAG_CANCEL: u8 = 2;

#[derive(Debug)]
pub(crate) enum DownloadError {
    Paused,
    Cancelled(String),
    Failed { message: String, recoverable: bool },
    DownloadUrlExpired,
}

impl DownloadError {
    pub(crate) fn message(&self) -> String {
        match self {
            DownloadError::Paused => "下载已暂停".to_string(),
            DownloadError::Cancelled(message) => message.clone(),
            DownloadError::Failed { message, .. } => message.clone(),
            DownloadError::DownloadUrlExpired => "下载链接已过期，请重试".to_string(),
        }
    }

    pub(crate) fn is_recoverable(&self) -> bool {
        match self {
            DownloadError::Failed { recoverable, .. } => *recoverable,
            DownloadError::DownloadUrlExpired => true,
            _ => false,
        }
    }
}

/// 下载指定 drive item（仅文件），保存到 target_dir。
/// - 优先使用 Graph 返回的 downloadUrl（免鉴权）。
/// - 若 downloadUrl 缺失，回退到 `/content` 并携带 token。
/// 对 Flutter 暴露的下载入口（保持原接口，内部委托到带进度的实现）。
#[flutter_rust_bridge::frb]
pub fn download_drive_item(
    item_id: String,
    target_dir: String,
    overwrite: bool,
) -> Result<DriveDownloadResult, String> {
    download_drive_item_internal(item_id, target_dir, overwrite, None, None)
        .map_err(|err| err.message())
}

/// 供下载管理器调用的进度版下载函数。
/// - `progress` 为可选回调，便于任务管理器实时同步进度。
#[allow(dead_code)]
pub(crate) fn download_drive_item_with_progress(
    item_id: String,
    target_dir: String,
    overwrite: bool,
    progress: Option<ProgressCallback>,
    control_flag: Option<Arc<AtomicU8>>,
) -> Result<DriveDownloadResult, DownloadError> {
    download_drive_item_internal(item_id, target_dir, overwrite, progress, control_flag)
}

/// 实际执行下载的内部实现，共享输入验证与文件保存逻辑。
fn download_drive_item_internal(
    item_id: String,
    target_dir: String,
    overwrite: bool,
    progress: Option<ProgressCallback>,
    control_flag: Option<Arc<AtomicU8>>,
) -> Result<DriveDownloadResult, DownloadError> {
    if item_id.trim().is_empty() {
        return Err(DownloadError::Failed {
            message: "drive item id is required".to_string(),
            recoverable: false,
        });
    }
    if target_dir.trim().is_empty() {
        return Err(DownloadError::Failed {
            message: "target directory is required".to_string(),
            recoverable: false,
        });
    }

    eprintln!("[drive-download] fetching metadata for item {}", item_id);
    let mut metadata = fetch_download_metadata(&item_id)?;
    if metadata.file.is_none() {
        eprintln!(
            "[drive-download] item {} has no file facet (name={:?})",
            item_id, metadata.name
        );
        return Err(DownloadError::Failed {
            message: "选中的项目不是可下载的文件".to_string(),
            recoverable: false,
        });
    }

    let file_name = metadata
        .name
        .as_deref()
        .map(sanitize_file_name)
        .unwrap_or_else(|| "download.bin".to_string());

    let destination = prepare_destination(&target_dir, &file_name, overwrite)?;
    let progress_cell = progress.map(RefCell::new);
    let mut attempts = 0;
    let bytes_downloaded = loop {
        let fallback_token = if metadata.download_url.is_none() {
            Some(current_access_token().map_err(|message| DownloadError::Failed {
                message,
                recoverable: false,
            })?)
        } else {
            None
        };
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
                (content_url, fallback_token)
            }
        };

        let result = {
            let mut progress_guard =
                progress_cell.as_ref().map(|cell| cell.borrow_mut());
            let progress_ref = progress_guard.as_deref_mut().map(|cb| {
                cb.as_mut() as &mut (dyn FnMut(u64, Option<u64>) + Send)
            });
            stream_download(
                &download_endpoint,
                bearer_token,
                &destination,
                metadata.size,
                None,
                progress_ref,
                control_flag.as_ref(),
            )
        };
        match result {
            Ok(bytes) => break bytes,
            Err(DownloadError::DownloadUrlExpired) if attempts == 0 => {
                attempts += 1;
                eprintln!(
                    "[drive-download] downloadUrl expired for {}, refreshing metadata",
                    item_id
                );
                metadata = fetch_download_metadata(&item_id)?;
                continue;
            }
            Err(err) => return Err(err),
        }
    };
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

pub(crate) fn fetch_download_metadata(item_id: &str) -> Result<DriveItemDownloadDto, DownloadError> {
    // 单次请求只关心必要字段，避免传输冗余信息。
    let client = build_blocking_client(Duration::from_secs(30)).map_err(|message| {
        DownloadError::Failed {
            message,
            recoverable: false,
        }
    })?;
    let url = format!(
        "{GRAPH_BASE}/me/drive/items/{item_id}?$select=name,size,file,eTag,@microsoft.graph.downloadUrl"
    );
    let response = send_with_refresh(|token| {
        client
            .get(&url)
            .bearer_auth(token)
            .header("Accept", "application/json")
            .send()
            .map_err(|e| format!("failed to fetch download metadata: {e}"))
    })
    .map_err(|message| DownloadError::Failed {
        recoverable: is_recoverable_fetch_error(&message),
        message,
    })?;

    if response.status().as_u16() == 401 {
        return Err(DownloadError::Failed {
            message: "access token rejected by Graph API; please sign in again".to_string(),
            recoverable: false,
        });
    }
    if response.status().as_u16() == 404 {
        return Err(DownloadError::Failed {
            message: "找不到指定的文件，可能已经被移动或删除".to_string(),
            recoverable: false,
        });
    }
    if !response.status().is_success() {
        return Err(DownloadError::Failed {
            message: format!(
                "graph api returned HTTP {} while fetching download info",
                response.status()
            ),
            recoverable: response.status().is_server_error(),
        });
    }

    response
        .json::<DriveItemDownloadDto>()
        .map_err(|e| DownloadError::Failed {
            message: format!("failed to parse download metadata: {e}"),
            recoverable: false,
        })
}

fn is_recoverable_fetch_error(message: &str) -> bool {
    let lower = message.to_lowercase();
    if lower.contains("no authentication state") {
        return false;
    }
    if lower.contains("no refresh token") {
        return false;
    }
    if lower.contains("interactive authentication required") {
        return false;
    }
    if lower.contains("invalid_grant") {
        return false;
    }
    if lower.contains("interaction_required") {
        return false;
    }
    if lower.contains("login_required") {
        return false;
    }
    if lower.contains("consent_required") {
        return false;
    }
    if lower.contains("aadsts") {
        return false;
    }

    const MARKER: &str = "token endpoint returned http ";
    if let Some(index) = lower.find(MARKER) {
        let tail = lower[index + MARKER.len()..].trim_start();
        if let Some(code_str) = tail.split_whitespace().next() {
            if let Ok(code) = code_str.parse::<u16>() {
                if (400..500).contains(&code) && code != 429 {
                    return false;
                }
            }
        }
    }

    true
}

/// 对 Graph 返回的文件名进行清洗，兼容不同桌面平台的非法字符。
pub(crate) fn sanitize_file_name(raw: &str) -> String {
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
pub(crate) fn prepare_destination(
    target_dir: &str,
    file_name: &str,
    overwrite: bool,
) -> Result<PathBuf, DownloadError> {
    let dir_path = Path::new(target_dir);
    fs::create_dir_all(dir_path).map_err(|e| DownloadError::Failed {
        message: format!("无法创建下载目录 {}: {e}", dir_path.to_string_lossy()),
        recoverable: false,
    })?;

    let destination = dir_path.join(file_name);
    if destination.exists() && !overwrite {
        return Err(DownloadError::Failed {
            message: format!(
                "文件已存在：{}（如需覆盖请设置 overwrite=true）",
                destination.to_string_lossy()
            ),
            recoverable: false,
        });
    }

    Ok(destination)
}

/// 实际执行 HTTP 下载并流式写入磁盘，必要时附带 Bearer token。
/// 逐块读取响应体，写入文件后触发进度回调，确保 UI 能看到实时变化。
pub(crate) fn stream_download<'a>(
    download_url: &str,
    bearer_token: Option<String>,
    destination: &Path,
    total_size: Option<u64>,
    resume_from: Option<u64>,
    progress: Option<&'a mut (dyn FnMut(u64, Option<u64>) + Send + 'a)>,
    control_flag: Option<&Arc<AtomicU8>>,
) -> Result<u64, DownloadError> {
    stream_download_internal(
        download_url,
        bearer_token,
        destination,
        total_size,
        resume_from,
        progress,
        control_flag,
        true,
    )
}

fn stream_download_internal<'a>(
    download_url: &str,
    bearer_token: Option<String>,
    destination: &Path,
    total_size: Option<u64>,
    resume_from: Option<u64>,
    mut progress: Option<&'a mut (dyn FnMut(u64, Option<u64>) + Send + 'a)>,
    control_flag: Option<&Arc<AtomicU8>>,
    allow_refresh: bool,
) -> Result<u64, DownloadError> {
    let client =
        build_blocking_client(Duration::from_secs(600)).map_err(|message| DownloadError::Failed {
            message,
            recoverable: true,
        })?;
    let temp_path = PathBuf::from(format!("{}.part", destination.to_string_lossy()));

    let mut start_from = 0u64;
    if let Some(requested) = resume_from {
        if temp_path.exists() {
            let actual = fs::metadata(&temp_path)
                .map(|m| m.len())
                .unwrap_or(requested);
            start_from = actual;
        } else if requested > 0 {
            return Err(DownloadError::Failed {
                message: "续传文件已丢失，无法继续下载".to_string(),
                recoverable: false,
            });
        }
    } else if temp_path.exists() {
        let _ = fs::remove_file(&temp_path);
    }

    if let Some(expected) = total_size {
        if expected > 0 && start_from >= expected {
            let _ = fs::rename(&temp_path, destination);
            return Ok(start_from);
        }
    }

    let mut request = client.get(download_url);
    if let Some(token) = bearer_token.as_deref() {
        request = request.bearer_auth(token);
    }
    if start_from > 0 {
        request = request.header("Range", format!("bytes={start_from}-"));
    }
    let mut response = request
        .send()
        .map_err(|e| DownloadError::Failed {
            message: format!("failed to download file: {e}"),
            recoverable: true,
        })?;

    let status = response.status();
    if status.as_u16() == 401 {
        if allow_refresh && bearer_token.is_some() {
            let refreshed = refresh_access_token().map_err(|message| DownloadError::Failed {
                message,
                recoverable: false,
            })?;
            return stream_download_internal(
                download_url,
                Some(refreshed),
                destination,
                total_size,
                resume_from,
                progress,
                control_flag,
                false,
            );
        }
        if bearer_token.is_none() {
            return Err(DownloadError::DownloadUrlExpired);
        }
        return Err(DownloadError::Failed {
            message: "access token rejected by Graph API; please sign in again".to_string(),
            recoverable: false,
        });
    }
    if status.as_u16() == 416 {
        return Err(DownloadError::Failed {
            message: "无法继续续传，文件可能已更新或范围无效".to_string(),
            recoverable: false,
        });
    }
    if !(status.is_success() || status.as_u16() == 206) {
        return Err(DownloadError::Failed {
            message: format!("download endpoint returned HTTP {}", status),
            recoverable: true,
        });
    }

    if start_from > 0 && status.as_u16() == 200 {
        start_from = 0;
    }

    let mut file = OpenOptions::new()
        .create(true)
        .write(true)
        .open(&temp_path)
        .map_err(|e| DownloadError::Failed {
            message: format!(
                "failed to open temp file {}: {e}",
                temp_path.to_string_lossy()
            ),
            recoverable: false,
        })?;
    if start_from == 0 {
        file.set_len(0).map_err(|e| DownloadError::Failed {
            message: format!(
                "failed to truncate temp file {}: {e}",
                temp_path.to_string_lossy()
            ),
            recoverable: false,
        })?;
    } else {
        file.seek(SeekFrom::Start(start_from))
            .map_err(|e| DownloadError::Failed {
                message: format!(
                    "failed to seek temp file {}: {e}",
                    temp_path.to_string_lossy()
                ),
                recoverable: false,
            })?;
    }
    let mut writer = BufWriter::new(file);

    let mut downloaded = start_from;
    if let Some(ref mut cb) = progress {
        cb(downloaded, total_size);
    }

    let mut buffer = [0u8; 64 * 1024];
    loop {
        if let Some(flag) = control_flag {
            match flag.load(Ordering::Relaxed) {
                CONTROL_FLAG_CANCEL => {
                    drop(response);
                    drop(writer);
                    let _ = fs::remove_file(&temp_path);
                    return Err(DownloadError::Cancelled("下载已取消".to_string()));
                }
                CONTROL_FLAG_PAUSE => {
                    drop(response);
                    drop(writer);
                    return Err(DownloadError::Paused);
                }
                _ => {}
            }
        }
        let read_bytes = response
            .read(&mut buffer)
            .map_err(|e| DownloadError::Failed {
                message: format!("failed to read response body: {e}"),
                recoverable: true,
            })?;
        if read_bytes == 0 {
            break;
        }
        writer
            .write_all(&buffer[..read_bytes])
            .map_err(|e| DownloadError::Failed {
                message: format!("failed to write file: {e}"),
                recoverable: false,
            })?;
        downloaded += read_bytes as u64;
        if let Some(ref mut cb) = progress {
            cb(downloaded, total_size);
        }
    }
    writer
        .flush()
        .map_err(|e| DownloadError::Failed {
            message: format!("failed to flush file: {e}"),
            recoverable: false,
        })?;

    fs::rename(&temp_path, destination).map_err(|e| DownloadError::Failed {
        message: format!(
            "failed to finalize file {}: {e}",
            destination.to_string_lossy()
        ),
        recoverable: false,
    })?;

    Ok(downloaded)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct DriveItemDownloadDto {
    pub(crate) name: Option<String>,
    pub(crate) size: Option<u64>,
    pub(crate) file: Option<DriveFileFacet>,
    #[serde(rename = "eTag")]
    pub(crate) etag: Option<String>,
    #[serde(rename = "@microsoft.graph.downloadUrl")]
    pub(crate) download_url: Option<String>,
}

#[allow(dead_code)] // metadata 中可能暂时只读取 mime_type，因此关闭未使用告警
#[derive(Debug, Deserialize)]
pub(crate) struct DriveFileFacet {
    #[serde(rename = "mimeType")]
    mime_type: Option<String>,
}
