use std::collections::HashSet;
use std::time::Duration;

use reqwest::StatusCode;
use serde::Deserialize;

use crate::db::{self, OfflineIndexRecord, OfflineIndexTable};
use crate::settings::offline_index::{
    clear_offline_index_delta_link, get_offline_index_delta_link,
    get_offline_index_last_sync_millis, set_offline_index_delta_link,
    set_offline_index_last_sync_millis,
};

use super::client::{build_blocking_client, send_with_refresh};
use super::models::{DriveItemSummary, DrivePage, OfflineIndexStatus};
use super::GRAPH_BASE;

/// 离线分页 token 前缀（格式：`offline:<offset>`）。
const OFFLINE_SEARCH_TOKEN_PREFIX: &str = "offline:";
/// 默认离线搜索分页大小。
const DEFAULT_SEARCH_PAGE_SIZE: usize = 120;
/// 离线搜索分页上限，避免单页过大。
const MAX_SEARCH_PAGE_SIZE: usize = 500;
/// Delta 同步请求每页条数。
const DELTA_PAGE_TOP: usize = 200;
/// Delta 同步最大页数保护，防止异常循环。
const MAX_DELTA_PAGES: usize = 100_000;
/// 名称缺失时的兜底显示名。
const DEFAULT_ITEM_NAME: &str = "(unnamed)";

/// 对外入口：同步（增量优先）并返回最新离线索引状态。
#[flutter_rust_bridge::frb]
pub fn rebuild_offline_index() -> Result<OfflineIndexStatus, String> {
    sync_offline_index()
}

/// 查询离线索引状态（条数 + 最近同步时间）。
#[flutter_rust_bridge::frb]
pub fn get_offline_index_status() -> Result<OfflineIndexStatus, String> {
    let indexed_items = db::count_offline_index_items()?;
    let last_indexed_at_millis =
        get_offline_index_last_sync_millis()?.or(db::latest_offline_indexed_at_millis()?);
    Ok(OfflineIndexStatus {
        indexed_items: indexed_items.min(u32::MAX as usize) as u32,
        last_indexed_at_millis,
    })
}

/// 对离线索引执行分页搜索。
/// `next_link` 使用离线 token，不是 Graph URL。
#[flutter_rust_bridge::frb]
pub fn search_offline_index(
    query: String,
    folder_id: Option<String>,
    next_link: Option<String>,
    top: Option<u32>,
) -> Result<DrivePage, String> {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return Err("search query is required".to_string());
    }

    let offset = parse_offset(next_link.as_deref());
    let limit = normalize_page_size(top);
    let folded_query = trimmed.to_lowercase();
    let mut rows =
        db::search_offline_index_items(&folded_query, folder_id.as_deref(), limit + 1, offset)?;
    let has_more = rows.len() > limit;
    if has_more {
        rows.truncate(limit);
    }

    let items = rows.into_iter().map(map_to_summary).collect::<Vec<_>>();
    let next_link = if has_more {
        Some(format!("{OFFLINE_SEARCH_TOKEN_PREFIX}{}", offset + limit))
    } else {
        None
    };
    Ok(DrivePage { items, next_link })
}

/// 离线索引同步主流程：
/// 1. 尝试基于已保存 delta_link 做增量同步；
/// 2. token 失效时自动回退全量；
/// 3. 成功后写回新的 delta_link 和最后同步时间。
fn sync_offline_index() -> Result<OfflineIndexStatus, String> {
    let existing_link = get_offline_index_delta_link()?;
    let result: Result<String, SyncError> = if let Some(link) = existing_link {
        match apply_delta_sync(link, OfflineIndexTable::Main) {
            Ok(next_delta_link) => Ok(next_delta_link),
            Err(SyncError::ResetRequired(_)) => run_full_delta_sync(),
            Err(SyncError::Failed(message)) => Err(SyncError::Failed(message)),
        }
    } else {
        run_full_delta_sync()
    };

    let next_delta_link = result.map_err(sync_error_message)?;
    set_offline_index_delta_link(next_delta_link)?;
    let now = db::current_timestamp_millis();
    set_offline_index_last_sync_millis(now)?;
    get_offline_index_status()
}

/// 执行全量同步：
/// - 在 staging 表构建完整快照；
/// - 快照完成后原子替换主表，避免主表出现中间态。
fn run_full_delta_sync() -> Result<String, SyncError> {
    // Token 无效或缺失，强制完整快照。
    clear_offline_index_delta_link().map_err(SyncError::Failed)?;
    db::clear_offline_index_table(OfflineIndexTable::Staging).map_err(SyncError::Failed)?;
    let delta_link = apply_delta_sync(build_initial_delta_url(), OfflineIndexTable::Staging)?;
    db::replace_main_with_staging().map_err(SyncError::Failed)?;
    Ok(delta_link)
}

/// 从 `start_url` 开始消费 delta 分页，直到拿到 `@odata.deltaLink`。
fn apply_delta_sync(start_url: String, table: OfflineIndexTable) -> Result<String, SyncError> {
    let mut url = start_url;
    let mut page_count = 0usize;
    let mut seen_links = HashSet::<String>::new();
    let mut pending_folder_deletes = HashSet::<String>::new();

    loop {
        if page_count >= MAX_DELTA_PAGES {
            return Err(SyncError::Failed(format!(
                "delta sync exceeded max page limit ({MAX_DELTA_PAGES})"
            )));
        }
        page_count += 1;

        if !seen_links.insert(url.clone()) {
            return Err(SyncError::Failed(
                "delta returned a repeated nextLink".to_string(),
            ));
        }

        let page = fetch_delta_page(&url)?;
        apply_delta_items(table, page.value, &mut pending_folder_deletes)?;

        if let Some(next_link) = page.next_link {
            url = next_link;
            continue;
        }

        finalize_folder_deletes(table, pending_folder_deletes)?;

        if let Some(delta_link) = page.delta_link {
            return Ok(delta_link);
        }
        return Err(SyncError::Failed(
            "delta response missing both @odata.nextLink and @odata.deltaLink".to_string(),
        ));
    }
}

/// 应用一页 delta 变更到目标表：
/// - 删除事件：文件立即删，目录延迟删；
/// - 普通事件：按 item_id upsert，保证幂等；
/// - root 占位事件：忽略。
fn apply_delta_items(
    table: OfflineIndexTable,
    items: Vec<DeltaItemDto>,
    pending_folder_deletes: &mut HashSet<String>,
) -> Result<(), SyncError> {
    let indexed_at = db::current_timestamp_millis();
    for item in items {
        if item.deleted.is_some() {
            handle_deleted_item(table, &item.id, pending_folder_deletes)?;
            continue;
        }
        if item.root.is_some() {
            continue;
        }
        pending_folder_deletes.remove(&item.id);
        let existing = db::get_offline_index_item(table, &item.id).map_err(SyncError::Failed)?;
        let record = delta_item_to_record(item, existing, indexed_at);
        db::upsert_offline_index_item(table, &record).map_err(SyncError::Failed)?;
    }
    Ok(())
}

/// 处理单条删除事件。
/// 目录先加入待删集合，防止子项尚未处理完导致层级不一致。
fn handle_deleted_item(
    table: OfflineIndexTable,
    item_id: &str,
    pending_folder_deletes: &mut HashSet<String>,
) -> Result<(), SyncError> {
    let existing = db::get_offline_index_item(table, item_id).map_err(SyncError::Failed)?;
    let Some(existing) = existing else {
        return Ok(());
    };
    if existing.is_folder {
        pending_folder_deletes.insert(item_id.to_string());
        return Ok(());
    }
    db::delete_offline_index_item(table, item_id).map_err(SyncError::Failed)?;
    Ok(())
}

/// 对待删目录做“无子项才删除”的收敛清理。
fn finalize_folder_deletes(
    table: OfflineIndexTable,
    mut pending_folder_deletes: HashSet<String>,
) -> Result<(), SyncError> {
    if pending_folder_deletes.is_empty() {
        return Ok(());
    }

    loop {
        let mut progress = false;
        let pending_ids = pending_folder_deletes.iter().cloned().collect::<Vec<_>>();
        for folder_id in pending_ids {
            let has_children =
                db::has_offline_index_children(table, &folder_id).map_err(SyncError::Failed)?;
            if has_children {
                continue;
            }
            db::delete_offline_index_item(table, &folder_id).map_err(SyncError::Failed)?;
            pending_folder_deletes.remove(&folder_id);
            progress = true;
        }

        if pending_folder_deletes.is_empty() || !progress {
            break;
        }
    }

    Ok(())
}

/// 拉取并解析一页 delta 数据，同时做鉴权刷新和错误分类。
fn fetch_delta_page(url: &str) -> Result<DeltaPage, SyncError> {
    let client = build_blocking_client(Duration::from_secs(45))
        .map_err(|e| SyncError::Failed(format!("failed to build delta HTTP client: {e}")))?;
    let response = send_with_refresh(|token| {
        client
            .get(url)
            .bearer_auth(token)
            .header("Accept", "application/json")
            .send()
            .map_err(|e| format!("failed to sync delta page: {e}"))
    })
    .map_err(SyncError::Failed)?;

    if response.status().as_u16() == 401 {
        return Err(SyncError::Failed(
            "access token rejected by Graph API; please sign in again".to_string(),
        ));
    }

    if response.status().is_success() {
        return response
            .json::<DeltaPage>()
            .map_err(|e| SyncError::Failed(format!("failed to parse delta response: {e}")));
    }

    let status = response.status();
    let body_text = response
        .text()
        .unwrap_or_else(|_| "<unable to read error body>".to_string());
    if is_delta_reset(status, &body_text) {
        return Err(SyncError::ResetRequired(format!(
            "delta token reset requested by Graph (HTTP {status})"
        )));
    }
    Err(SyncError::Failed(format!(
        "graph delta api returned HTTP {status}: {body_text}"
    )))
}

/// 判断错误是否属于“delta token 失效，需要全量重建”。
fn is_delta_reset(status: StatusCode, body_text: &str) -> bool {
    if status == StatusCode::GONE {
        return true;
    }
    let parsed = serde_json::from_str::<GraphErrorEnvelope>(body_text);
    let Ok(envelope) = parsed else {
        return false;
    };
    let code = envelope.error.code.to_ascii_lowercase();
    let message = envelope.error.message.to_ascii_lowercase();
    if code == "syncstatenotfound" || code == "resyncrequired" {
        return true;
    }
    message.contains("invalid delta")
        || message.contains("invalid deltalink")
        || message.contains("delta token")
}

/// 构造初始全量 delta 请求 URL（带最小必要字段与分页参数）。
fn build_initial_delta_url() -> String {
    format!(
        "{GRAPH_BASE}/me/drive/root/delta?$select=id,name,size,lastModifiedDateTime,folder,file,parentReference&$expand=thumbnails($select=small,medium)&$top={DELTA_PAGE_TOP}"
    )
}

/// 将 Graph delta item 合并映射为本地索引记录。
/// 字段缺失时优先沿用旧值，降低“部分返回”导致的信息丢失。
fn delta_item_to_record(
    item: DeltaItemDto,
    existing: Option<OfflineIndexRecord>,
    indexed_at_millis: i64,
) -> OfflineIndexRecord {
    let previous = existing.unwrap_or_else(|| OfflineIndexRecord {
        item_id: item.id.clone(),
        parent_id: None,
        name: DEFAULT_ITEM_NAME.to_string(),
        name_folded: DEFAULT_ITEM_NAME.to_string(),
        is_folder: false,
        size: None,
        child_count: None,
        mime_type: None,
        last_modified: None,
        thumbnail_url: None,
        indexed_at_millis,
    });

    let mut name = item.name.unwrap_or(previous.name);
    if name.trim().is_empty() {
        name = DEFAULT_ITEM_NAME.to_string();
    }
    let is_folder = match (item.folder.as_ref(), item.file.as_ref()) {
        (Some(_), _) => true,
        (None, Some(_)) => false,
        (None, None) => previous.is_folder,
    };
    let parent_id = item
        .parent_reference
        .and_then(|parent| parent.id)
        .or(previous.parent_id);
    let size = item
        .size
        .and_then(|value| i64::try_from(value).ok())
        .or(previous.size);
    let child_count = if is_folder {
        item.folder
            .as_ref()
            .and_then(|folder| folder.child_count)
            .or(previous.child_count)
    } else {
        None
    };
    let mime_type = if is_folder {
        None
    } else {
        item.file
            .as_ref()
            .and_then(|file| file.mime_type.clone())
            .or(previous.mime_type)
    };
    let last_modified = item.last_modified_date_time.or(previous.last_modified);
    let thumbnail_url = item
        .thumbnails
        .and_then(|sets| sets.into_iter().find_map(ThumbnailSetDto::best_url))
        .or(previous.thumbnail_url);

    OfflineIndexRecord {
        item_id: item.id,
        parent_id,
        name_folded: name.to_lowercase(),
        name,
        is_folder,
        size,
        child_count,
        mime_type,
        last_modified,
        thumbnail_url,
        indexed_at_millis,
    }
}

/// 存储记录转回前端展示模型。
fn map_to_summary(record: OfflineIndexRecord) -> DriveItemSummary {
    DriveItemSummary {
        id: record.item_id,
        name: record.name,
        size: record.size.and_then(|value| u64::try_from(value).ok()),
        is_folder: record.is_folder,
        child_count: record.child_count,
        mime_type: record.mime_type,
        last_modified: record.last_modified,
        thumbnail_url: record.thumbnail_url,
    }
}

/// 规范化页大小，确保在允许范围内。
fn normalize_page_size(top: Option<u32>) -> usize {
    top.filter(|value| *value > 0)
        .map(|value| value as usize)
        .unwrap_or(DEFAULT_SEARCH_PAGE_SIZE)
        .min(MAX_SEARCH_PAGE_SIZE)
}

/// 从离线分页 token 中解析偏移量。
/// 解析失败一律回退首页，保证容错。
fn parse_offset(next_link: Option<&str>) -> usize {
    let raw = match next_link {
        Some(value) => value.trim(),
        None => return 0,
    };
    if !raw.starts_with(OFFLINE_SEARCH_TOKEN_PREFIX) {
        return 0;
    }
    let offset = &raw[OFFLINE_SEARCH_TOKEN_PREFIX.len()..];
    offset
        .parse::<usize>()
        .ok()
        .filter(|value| *value > 0)
        .unwrap_or(0)
}

/// 同步错误分类：
/// - `ResetRequired`：必须清空 token 并全量重建；
/// - `Failed`：普通失败，可重试。
#[derive(Debug)]
enum SyncError {
    ResetRequired(String),
    Failed(String),
}

/// Graph delta 分页响应体。
#[derive(Debug, Deserialize)]
struct DeltaPage {
    value: Vec<DeltaItemDto>,
    #[serde(rename = "@odata.nextLink")]
    next_link: Option<String>,
    #[serde(rename = "@odata.deltaLink")]
    delta_link: Option<String>,
}

/// Graph delta item（仅保留离线索引需要字段）。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DeltaItemDto {
    id: String,
    name: Option<String>,
    size: Option<u64>,
    #[serde(rename = "lastModifiedDateTime")]
    last_modified_date_time: Option<String>,
    folder: Option<DriveFolderFacet>,
    file: Option<DriveFileFacet>,
    #[serde(rename = "parentReference")]
    parent_reference: Option<ParentReferenceDto>,
    thumbnails: Option<Vec<ThumbnailSetDto>>,
    deleted: Option<DeletedFacet>,
    root: Option<serde_json::Value>,
}

/// 父引用，仅使用 id 建立目录关系。
#[derive(Debug, Deserialize)]
struct ParentReferenceDto {
    id: Option<String>,
}

/// 目录 facet。
#[derive(Debug, Deserialize)]
struct DriveFolderFacet {
    #[serde(rename = "childCount")]
    child_count: Option<i64>,
}

/// 文件 facet。
#[derive(Debug, Deserialize)]
struct DriveFileFacet {
    #[serde(rename = "mimeType")]
    mime_type: Option<String>,
}

/// 缩略图集合。
#[derive(Debug, Deserialize)]
struct ThumbnailSetDto {
    small: Option<ThumbnailDto>,
    medium: Option<ThumbnailDto>,
    large: Option<ThumbnailDto>,
}

/// 单个缩略图节点。
#[derive(Debug, Deserialize)]
struct ThumbnailDto {
    url: Option<String>,
}

/// 删除标记（字段内容不使用，仅判空）。
#[derive(Debug, Deserialize)]
struct DeletedFacet {}

/// Graph 错误 envelope。
#[derive(Debug, Deserialize)]
struct GraphErrorEnvelope {
    error: GraphErrorPayload,
}

/// Graph 错误核心字段。
#[derive(Debug, Deserialize)]
struct GraphErrorPayload {
    code: String,
    message: String,
}

impl ThumbnailSetDto {
    /// 选择最合适的缩略图 URL，优先 small 以减小流量。
    fn best_url(self) -> Option<String> {
        self.small
            .and_then(|thumb| thumb.url)
            .or_else(|| self.medium.and_then(|thumb| thumb.url))
            .or_else(|| self.large.and_then(|thumb| thumb.url))
    }
}

/// 将内部错误转换为统一错误文案。
fn sync_error_message(err: SyncError) -> String {
    match err {
        SyncError::ResetRequired(message) => message,
        SyncError::Failed(message) => message,
    }
}
