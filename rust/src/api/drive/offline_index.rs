use std::collections::{HashSet, VecDeque};

use crate::db::{self, OfflineIndexRecord};

use super::{
    list::list_drive_children,
    models::{DriveItemSummary, DrivePage, OfflineIndexStatus},
};

const OFFLINE_SEARCH_TOKEN_PREFIX: &str = "offline:";
const DEFAULT_SEARCH_PAGE_SIZE: usize = 120;
const MAX_SEARCH_PAGE_SIZE: usize = 500;

#[flutter_rust_bridge::frb]
pub fn rebuild_offline_index() -> Result<OfflineIndexStatus, String> {
    let indexed_at = db::current_timestamp_millis();
    let records = collect_records(indexed_at)?;
    db::replace_offline_index(&records)?;
    get_offline_index_status()
}

#[flutter_rust_bridge::frb]
pub fn get_offline_index_status() -> Result<OfflineIndexStatus, String> {
    let indexed_items = db::count_offline_index_items()?;
    let last_indexed_at_millis = db::latest_offline_indexed_at_millis()?;
    Ok(OfflineIndexStatus {
        indexed_items: indexed_items.min(u32::MAX as usize) as u32,
        last_indexed_at_millis,
    })
}

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

fn collect_records(indexed_at_millis: i64) -> Result<Vec<OfflineIndexRecord>, String> {
    let mut records = Vec::new();
    let mut queue: VecDeque<Option<String>> = VecDeque::new();
    let mut visited_folders = HashSet::<String>::new();
    queue.push_back(None);

    while let Some(folder_id) = queue.pop_front() {
        if let Some(current) = folder_id.as_ref() {
            if !visited_folders.insert(current.clone()) {
                continue;
            }
        }

        let mut next_link: Option<String> = None;
        loop {
            let page = list_drive_children(folder_id.clone(), None, next_link.clone())?;
            for item in page.items {
                let item_id = item.id.clone();
                if item.is_folder {
                    queue.push_back(Some(item_id));
                }
                records.push(to_record(item, folder_id.clone(), indexed_at_millis));
            }
            next_link = page.next_link;
            if next_link.is_none() {
                break;
            }
        }
    }

    Ok(records)
}

fn to_record(
    item: DriveItemSummary,
    parent_id: Option<String>,
    indexed_at_millis: i64,
) -> OfflineIndexRecord {
    OfflineIndexRecord {
        item_id: item.id,
        parent_id,
        name_folded: item.name.to_lowercase(),
        name: item.name,
        is_folder: item.is_folder,
        size: item.size.and_then(|value| i64::try_from(value).ok()),
        child_count: item.child_count,
        mime_type: item.mime_type,
        last_modified: item.last_modified,
        thumbnail_url: item.thumbnail_url,
        indexed_at_millis,
    }
}

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

fn normalize_page_size(top: Option<u32>) -> usize {
    top.filter(|value| *value > 0)
        .map(|value| value as usize)
        .unwrap_or(DEFAULT_SEARCH_PAGE_SIZE)
        .min(MAX_SEARCH_PAGE_SIZE)
}

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
