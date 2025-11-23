use super::{
    client::{build_blocking_client, current_access_token},
    models::DriveItemSummary,
    GRAPH_BASE,
};
use percent_encoding::{utf8_percent_encode, NON_ALPHANUMERIC};
use serde::Deserialize;
use std::fs::File;
use std::io::{BufReader, Cursor, Read, Seek, SeekFrom};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::time::Duration;
use std::thread;

/// Graph 简易上传的官方上限（单请求），超出需走分片上传。
const SIMPLE_UPLOAD_MAX_BYTES: usize = 250 * 1024 * 1024;
// 分片上传推荐 5-10MiB，需满足 320KiB 对齐；10MiB 正好 32 * 320KiB。
const CHUNK_SIZE_BYTES: u64 = 10 * 1024 * 1024;
const CHUNK_ALIGNMENT: u64 = 320 * 1024;
const MAX_RETRY: usize = 4;
const RETRY_BASE_DELAY_MS: u64 = 400;

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
    upload_small_file_with_hooks(parent_id, file_name, content, overwrite, None, None)
}

#[allow(dead_code)]
#[flutter_rust_bridge::frb(ignore)]
pub(crate) fn upload_small_file_with_hooks(
    parent_id: Option<String>,
    file_name: String,
    content: Vec<u8>,
    overwrite: bool,
    cancel_flag: Option<Arc<AtomicBool>>,
    progress: Option<Box<dyn FnMut(u64, Option<u64>) + Send>>,
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

    let total_len = content.len() as u64;
    let reader = ProgressReader::new(
        Cursor::new(content),
        total_len,
        cancel_flag.clone(),
        progress,
    );
    let response = client
        .put(url)
        .bearer_auth(access_token)
        .header("Content-Type", "application/octet-stream")
        .body(reqwest::blocking::Body::sized(reader, total_len))
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

/// 创建分片上传会话，返回预签名 URL 与过期时间。
#[flutter_rust_bridge::frb(ignore)]
pub(crate) fn create_upload_session(
    parent_id: Option<String>,
    file_name: &str,
    overwrite: bool,
) -> Result<UploadSessionResponse, String> {
    let access_token = current_access_token()?;
    let client = build_blocking_client(Duration::from_secs(30))?;

    let encoded_name = utf8_percent_encode(file_name.trim(), NON_ALPHANUMERIC).to_string();
    let encoded_parent = parent_id
        .as_ref()
        .map(|id| id.trim().to_string())
        .filter(|id| !id.is_empty());

    let conflict = if overwrite { "replace" } else { "rename" };
    let url = if let Some(id) = encoded_parent {
        format!(
            "{GRAPH_BASE}/me/drive/items/{id}:/{encoded_name}:/createUploadSession"
        )
    } else {
        format!("{GRAPH_BASE}/me/drive/root:/{encoded_name}:/createUploadSession")
    };

    #[derive(serde::Serialize)]
    struct SessionRequestItem<'a> {
        #[serde(rename = "@microsoft.graph.conflictBehavior")]
        conflict_behavior: &'a str,
        name: &'a str,
    }
    #[derive(serde::Serialize)]
    struct SessionRequest<'a> {
        item: SessionRequestItem<'a>,
    }

    let body = SessionRequest {
        item: SessionRequestItem {
            conflict_behavior: conflict,
            name: file_name,
        },
    };

    let resp = client
        .post(url)
        .bearer_auth(access_token)
        .json(&body)
        .send()
        .map_err(|e| format!("failed to create upload session: {e}"))?;

    if resp.status().as_u16() == 401 {
        return Err("access token rejected by Graph API; please sign in again".to_string());
    }

    if !resp.status().is_success() {
        return Err(format!(
            "graph api returned HTTP {} while creating upload session",
            resp.status()
        ));
    }

    parse_upload_session_response(resp, "parse upload session", true)
}

/// 获取 upload session 状态（恢复/处理 416 时使用）。
#[flutter_rust_bridge::frb(ignore)]
pub(crate) fn get_upload_session_status(upload_url: &str) -> Result<UploadSessionResponse, String> {
    let client = build_blocking_client(Duration::from_secs(30))?;
    let resp = client
        .get(upload_url)
        .send()
        .map_err(|e| format!("failed to query upload session: {e}"))?;
    if resp.status().as_u16() == 404 {
        return Err("upload session expired or not found".to_string());
    }
    if !resp.status().is_success() {
        return Err(format!(
            "failed to query upload session, http {}",
            resp.status()
        ));
    }
    parse_upload_session_response(resp, "parse upload session status", false)
}

/// 分片上传大文件（读取本地路径），支持取消与进度回调。
#[flutter_rust_bridge::frb(ignore)]
pub(crate) fn upload_large_file_with_hooks(
    upload_url: String,
    local_path: &str,
    total_size: u64,
    mut offset: u64,
    cancel_flag: Arc<AtomicBool>,
    mut progress: Option<Box<dyn FnMut(u64, Option<u64>) + Send>>,
) -> Result<DriveItemSummary, String> {
    align_chunk_size()?;
    let mut file = File::open(local_path)
        .map_err(|e| format!("failed to open file for upload: {e}"))?;
    file.seek(SeekFrom::Start(offset))
        .map_err(|e| format!("failed to seek file: {e}"))?;
    let mut reader = BufReader::new(file);

    loop {
        if cancel_flag.load(Ordering::Relaxed) {
            // 尝试通知服务端取消会话，但即便失败也返回取消。
            let _ = cancel_upload_session(&upload_url);
            return Err("upload cancelled".to_string());
        }

        if offset >= total_size {
            // 所有分片上传完毕，查询最终结果。
            let status = get_upload_session_status(&upload_url)?;
            if let Some(item) = status.drive_item {
                if let Some(cb) = progress.as_mut() {
                    cb(total_size, Some(total_size));
                }
                return Ok(item.into());
            }
        }

        let remaining = total_size.saturating_sub(offset);
        let chunk_len = std::cmp::min(CHUNK_SIZE_BYTES, remaining) as usize;
        let mut buffer = vec![0u8; chunk_len];
        let n = reader
            .read(&mut buffer)
            .map_err(|e| format!("failed to read file chunk: {e}"))?;
        if n == 0 {
            return Err("unexpected EOF while reading file".to_string());
        }
        buffer.truncate(n);
        let end = offset + buffer.len() as u64 - 1;

        match upload_chunk_with_retry(
            &upload_url,
            offset,
            end,
            total_size,
            buffer,
            &cancel_flag,
        ) {
            Ok(UploadChunkResult::Continue { next_offset, expire_at: _ }) => {
                offset = next_offset;
                if let Some(cb) = progress.as_mut() {
                    cb(offset, Some(total_size));
                }
            }
            Ok(UploadChunkResult::Completed { item }) => {
                if let Some(cb) = progress.as_mut() {
                    cb(total_size, Some(total_size));
                }
                return Ok(item);
            }
            Err(UploadChunkError::RangeMismatch(next_start)) => {
                // 416/错位：重置游标后继续。
                offset = next_start;
                reader
                    .seek(SeekFrom::Start(offset))
                    .map_err(|e| format!("failed to seek after range mismatch: {e}"))?;
            }
            Err(UploadChunkError::SessionExpired) => {
                return Err("upload session expired; please retry".to_string());
            }
            Err(UploadChunkError::Cancelled) => {
                let _ = cancel_upload_session(&upload_url);
                return Err("upload cancelled".to_string());
            }
            Err(UploadChunkError::Fatal(msg)) => {
                return Err(msg);
            }
        }
    }
}

fn align_chunk_size() -> Result<(), String> {
    if CHUNK_SIZE_BYTES % CHUNK_ALIGNMENT != 0 {
        return Err("CHUNK_SIZE_BYTES must align with 320KiB per Graph requirement".to_string());
    }
    Ok(())
}

/// 处理单个分片上传，并包含指数退避重试。
fn upload_chunk_with_retry(
    upload_url: &str,
    start: u64,
    end: u64,
    total: u64,
    body: Vec<u8>,
    cancel_flag: &Arc<AtomicBool>,
) -> Result<UploadChunkResult, UploadChunkError> {
    let content_length = body.len() as u64;
    let content_range = format!("bytes {start}-{end}/{total}");

    let mut attempt = 0;
    let mut last_err = String::new();
    while attempt <= MAX_RETRY {
        if cancel_flag.load(Ordering::Relaxed) {
            return Err(UploadChunkError::Cancelled);
        }
        let client = build_blocking_client(Duration::from_secs(120))
            .map_err(|e| UploadChunkError::Fatal(format!("failed to build client: {e}")))?;
        let send_body = body.clone();
        let resp = client
            .put(upload_url)
            .header("Content-Length", content_length)
            .header("Content-Range", &content_range)
            .body(send_body)
            .send();
        match resp {
            Ok(r) => {
                let status = r.status();
                if status.is_success() {
                    if status.as_u16() == 201 || status.as_u16() == 200 {
                        let dto: DriveItemUploadResponse = r
                            .json()
                            .map_err(|e| UploadChunkError::Fatal(format!("parse final response failed: {e}")))?;
                        return Ok(UploadChunkResult::Completed { item: dto.into() });
                    }
                    // 202 Accepted: 继续上传
                    let dto = parse_upload_session_response(
                        r,
                        "parse upload session status after chunk",
                        false,
                    )
                    .map_err(UploadChunkError::Fatal)?;
                    let next_offset =
                        parse_next_start(&dto.next_expected_ranges).unwrap_or(end + 1);
                    return Ok(UploadChunkResult::Continue {
                        next_offset,
                        expire_at: dto.expiration_date_time,
                    });
                }
                match status.as_u16() {
                    401 => return Err(UploadChunkError::Fatal("access token rejected by Graph API; please sign in again".to_string())),
                    404 => return Err(UploadChunkError::SessionExpired),
                    409 => return Err(UploadChunkError::Fatal("upload conflict: target file changed, please retry".to_string())),
                    412 => return Err(UploadChunkError::Fatal("precondition failed while uploading; retry later".to_string())),
                    416 => {
                        if let Ok(status) = get_upload_session_status(upload_url) {
                            let next = parse_next_start(&status.next_expected_ranges).unwrap_or(start);
                            return Err(UploadChunkError::RangeMismatch(next));
                        } else {
                            return Err(UploadChunkError::RangeMismatch(start));
                        }
                    }
                    _ => {
                        last_err = format!("graph returned HTTP {status} for chunk {content_range}");
                    }
                }
            }
            Err(e) => {
                last_err = format!("network error on upload chunk: {e}");
            }
        }

        attempt += 1;
        if attempt > MAX_RETRY {
            break;
        }
        let backoff = RETRY_BASE_DELAY_MS * 2u64.saturating_pow(attempt as u32);
        thread::sleep(Duration::from_millis(backoff));
    }

    Err(UploadChunkError::Fatal(last_err))
}

fn cancel_upload_session(upload_url: &str) -> Result<(), String> {
    let client = build_blocking_client(Duration::from_secs(10))?;
    let resp = client
        .delete(upload_url)
        .send()
        .map_err(|e| format!("failed to cancel upload session: {e}"))?;
    if resp.status().is_success() || resp.status().as_u16() == 404 {
        Ok(())
    } else {
        Err(format!(
            "failed to cancel upload session, http {}",
            resp.status()
        ))
    }
}

fn parse_next_start(next_expected: &Option<Vec<String>>) -> Option<u64> {
    let raw = next_expected.as_ref()?.first()?;
    if let Some((start, _)) = raw.split_once('-') {
        return start.parse::<u64>().ok();
    }
    raw.parse::<u64>().ok()
}

fn parse_upload_session_response(
    resp: reqwest::blocking::Response,
    context: &str,
    require_upload_url: bool,
) -> Result<UploadSessionResponse, String> {
    let status = resp.status();
    let text = resp
        .text()
        .map_err(|e| format!("{context}: read body failed: {e} (http {status})"))?;
    let parsed: UploadSessionResponse = serde_json::from_str::<UploadSessionResponse>(&text).map_err(|e| {
        let snippet: String = text.chars().take(500).collect();
        format!(
            "{context}: parse failed ({e}) http {status}, body_snippet={snippet}"
        )
    })?;
    if require_upload_url && parsed.upload_url.is_none() {
        return Err(format!(
            "{context}: missing uploadUrl field http {status}, body_snippet={}",
            text.chars().take(200).collect::<String>()
        ));
    }
    Ok(parsed)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
pub(crate) struct UploadSessionResponse {
    #[serde(rename = "uploadUrl")]
    pub upload_url: Option<String>,
    #[serde(rename = "expirationDateTime")]
    pub expiration_date_time: Option<String>,
    #[serde(default)]
    pub next_expected_ranges: Option<Vec<String>>,
    #[serde(rename = "item")]
    pub drive_item: Option<DriveItemUploadResponse>,
}

enum UploadChunkResult {
    Continue {
        next_offset: u64,
        #[allow(dead_code)]
        expire_at: Option<String>,
    },
    Completed {
        item: DriveItemSummary,
    },
}

enum UploadChunkError {
    Cancelled,
    SessionExpired,
    RangeMismatch(u64),
    Fatal(String),
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
#[flutter_rust_bridge::frb(ignore)]
pub(crate) struct DriveItemUploadResponse {
    pub id: String,
    name: Option<String>,
    size: Option<u64>,
    #[serde(rename = "lastModifiedDateTime")]
    last_modified_date_time: Option<String>,
    file: Option<UploadFileFacet>,
}

#[derive(Debug, Deserialize)]
#[flutter_rust_bridge::frb(ignore)]
pub(crate) struct UploadFileFacet {
    #[serde(rename = "mimeType")]
    pub mime_type: Option<String>,
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

/// 负责对上传请求体做进度回调与取消检测的 Reader。
struct ProgressReader<R: Read> {
    inner: R,
    sent: u64,
    total: u64,
    cancel_flag: Option<Arc<AtomicBool>>,
    progress: Option<Box<dyn FnMut(u64, Option<u64>) + Send>>,
}

impl<R: Read> ProgressReader<R> {
    fn new(
        inner: R,
        total: u64,
        cancel_flag: Option<Arc<AtomicBool>>,
        progress: Option<Box<dyn FnMut(u64, Option<u64>) + Send>>,
    ) -> Self {
        Self {
            inner,
            sent: 0,
            total,
            cancel_flag,
            progress,
        }
    }
}

impl<R: Read> Read for ProgressReader<R> {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        if let Some(flag) = self.cancel_flag.as_ref() {
            if flag.load(Ordering::Relaxed) {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::Interrupted,
                    "upload cancelled",
                ));
            }
        }
        let read_bytes = self.inner.read(buf)?;
        if read_bytes > 0 {
            self.sent = self.sent.saturating_add(read_bytes as u64);
            if let Some(cb) = self.progress.as_mut() {
                cb(self.sent, Some(self.total));
            }
        }
        Ok(read_bytes)
    }
}
