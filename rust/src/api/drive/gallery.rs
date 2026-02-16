//! 图库（Gallery）相关 API。
//!
//! 这里的“图库”主要对应 Microsoft Graph 的 `drive/special/photos` 目录。
//! 需要注意：Graph 返回的 `children` 列表里可能混入视频或其他非图片条目，
//! 而 UI 通常只期望拿到可预览的图片，因此在 Rust 侧做过滤后再返回。
//!
//! 设计要点：
//! - 分页：支持使用 Graph 返回的 `@odata.nextLink`（这里抽象为 `next_link`）继续拉取下一页。
//! - 过滤：优先根据 `mime_type` 判断是否为图片；缺失时再用文件扩展名兜底。
//! - “空页”处理：如果某一页的所有条目都被过滤掉，会向后“预读”最多若干页，尽量避免前端出现空白分页。
//! - 回退扫描：极少数租户/账户下 `special/photos` 可能为空，但照片实际位于 root 下的其他目录。
//!   仅在首次请求且图库为空时，才进行 root 目录的有限递归扫描做兜底，避免影响正常分页性能。
use super::{
    list::{fetch_drive_page, THUMBNAIL_QUERY},
    models::{DriveItemSummary, DrivePage},
    GRAPH_BASE,
};
use std::collections::VecDeque;

/// 首次加载未指定 `$top` 时的默认分页大小。
const DEFAULT_PAGE_TOP: u32 = 120;

/// 当某一页过滤后变成空页时，最多向后再尝试读取多少页。
///
/// 这个“预读”上限用于避免在图片非常稀少或目录异常的情况下，出现过多网络请求。
const MAX_FILTER_LOOKAHEAD_PAGES: usize = 4;

/// root 回退扫描时，最多扫描多少个文件夹（BFS 队列弹出的次数）。
///
/// 这是兜底路径，不追求“全量找到所有图片”，主要目标是尽快凑够首屏需要的数据，
/// 同时限制最坏情况下的耗时与请求量。
const ROOT_SCAN_MAX_FOLDERS: usize = 120;

/// root 回退扫描时，每个文件夹最多翻多少页（通过 nextLink 继续读取）。
///
/// 避免某个目录过大导致兜底扫描“卡死”在单一目录里。
const ROOT_SCAN_MAX_PAGES_PER_FOLDER: usize = 4;

/// root 回退扫描时，每次请求使用的 `$top`。
///
/// 兜底路径一般只在首屏使用，因此允许一次拉取稍多条目，以减少分页次数。
const ROOT_SCAN_PAGE_TOP: u32 = 200;

/// 拉取图库（photos special folder）中的图片项，支持分页。
///
/// 参数说明：
/// - `next_link`：上一页返回的 `next_link`；为 `None` 表示拉取首屏（从 `special/photos` 开始）。
/// - `top`：Graph 分页大小（`$top`）。为 `None` 或 `<= 0` 时使用默认值。
///
/// 返回值：
/// - `Ok(DrivePage)`：`items` 仅包含被识别为“图片”的条目；`next_link` 用于继续分页。
/// - `Err(String)`：网络/解析等错误统一用字符串向上抛给 Flutter 层（符合当前仓库的错误模型）。
///
/// 行为说明：
/// - Graph 的 photos 目录可能混入视频等非图片条目，这里会在 Rust 侧过滤后再返回给 UI。
/// - 当某一页全部被过滤掉时，会自动向后预读最多若干页，尽量避免前端出现“空白分页”。
/// - 某些租户/账户下 `special/photos` 可能为空：仅在“首屏请求 + 确认为空”时回退到 root 扫描兜底。
///   兜底扫描不提供可继续分页的 `next_link`，仅用于尽快返回一批图片供 UI 展示。
#[flutter_rust_bridge::frb]
pub fn list_drive_gallery_items(
    next_link: Option<String>,
    top: Option<u32>,
) -> Result<DrivePage, String> {
    // next_link 存在时直接用它继续分页；否则构造 special/photos 的首屏 URL。
    let initial_url = next_link
        .as_ref()
        .cloned()
        .unwrap_or_else(|| build_gallery_children_url(top));
    let page = fetch_gallery_page_filtered(initial_url)?;

    // 某些租户/账户下 special/photos 可能为空，但图片实际位于其他目录（例如 root:/Photo）。
    // 仅在首屏且 special/photos 返回空结果时回退到 root 递归扫描，避免影响正常分页路径。
    if next_link.is_none() && page.items.is_empty() && page.next_link.is_none() {
        return scan_gallery_items_from_root(top);
    }

    Ok(page)
}

/// 构造 `special/photos/children` 的请求 URL，并附带缩略图查询与 `$top`。
///
/// 这里不会附带 `$skiptoken` 等分页参数；后续分页统一交给 Graph 的 `next_link`。
fn build_gallery_children_url(top: Option<u32>) -> String {
    let mut url = format!("{GRAPH_BASE}/me/drive/special/photos/children{THUMBNAIL_QUERY}");
    let page_top = top.filter(|v| *v > 0).unwrap_or(DEFAULT_PAGE_TOP);
    url.push_str(&format!("&$top={page_top}"));
    url
}

/// 拉取一页（或向后预读若干页）并过滤出“图片条目”。
///
/// 为什么需要“预读”：
/// - Graph 可能在同一分页里混入视频等条目，过滤后可能出现 `items` 为空；
/// - 如果直接返回空页，前端分页体验会很差（看起来像“没数据了”或“空白页”）。
///
/// 策略：
/// - 先拉取 `initial_url`；
/// - 过滤后若仍为空且存在 `next_link`，则继续使用 `next_link` 再拉取下一页；
/// - 直到拿到至少 1 条图片、或没有 `next_link`、或达到 `MAX_FILTER_LOOKAHEAD_PAGES` 上限为止。
fn fetch_gallery_page_filtered(initial_url: String) -> Result<DrivePage, String> {
    let mut request_url = initial_url;
    let mut filtered_items = Vec::new();
    let mut next_link: Option<String>;
    let mut lookahead_pages = 0usize;

    loop {
        let page = fetch_drive_page(&request_url)?;
        filtered_items.extend(page.items.into_iter().filter(is_gallery_image_item));
        next_link = page.next_link;

        if !filtered_items.is_empty()
            || next_link.is_none()
            || lookahead_pages >= MAX_FILTER_LOOKAHEAD_PAGES
        {
            break;
        }

        request_url = next_link
            .clone()
            .ok_or_else(|| "missing next link for gallery pagination".to_string())?;
        lookahead_pages += 1;
    }

    Ok(DrivePage {
        items: filtered_items,
        next_link,
    })
}

/// 当 `special/photos` 为空时，从 root 做一次“有限递归扫描”，尽量找到一些图片用于首屏展示。
///
/// 重要限制与取舍：
/// - 这是兜底路径，不追求“找到所有图片”，优先保证性能与可控性。
/// - 扫描采用 BFS（队列）逐层遍历文件夹；遇到子文件夹就入队，遇到文件则尝试识别是否为图片。
/// - 为避免最坏情况下大量请求，限制了：
///   - 最多扫描的文件夹数 `ROOT_SCAN_MAX_FOLDERS`
///   - 每个文件夹最多翻页次数 `ROOT_SCAN_MAX_PAGES_PER_FOLDER`
///   - 每次请求条目数 `$top = ROOT_SCAN_PAGE_TOP`
/// - 返回的 `DrivePage.next_link` 固定为 `None`：该兜底结果不具备稳定的分页语义。
fn scan_gallery_items_from_root(top: Option<u32>) -> Result<DrivePage, String> {
    let target = top.filter(|v| *v > 0).unwrap_or(DEFAULT_PAGE_TOP) as usize;
    let mut images = Vec::new();
    // `None` 表示从 root 开始；`Some(folder_id)` 表示扫描该文件夹的 children。
    let mut folder_queue: VecDeque<Option<String>> = VecDeque::from([None]);
    let mut scanned_folders = 0usize;

    while let Some(folder_id) = folder_queue.pop_front() {
        if scanned_folders >= ROOT_SCAN_MAX_FOLDERS || images.len() >= target {
            break;
        }
        scanned_folders += 1;

        let mut next_link: Option<String> = None;
        let mut page_count = 0usize;

        loop {
            // 同一个文件夹的分页由 Graph 的 nextLink 驱动；第一页则构造 children URL。
            let request_url = if let Some(link) = next_link.clone() {
                link
            } else {
                build_children_url_for_folder(folder_id.as_deref())
            };

            let page = fetch_drive_page(&request_url)?;
            for item in page.items {
                // 文件夹入队，后续继续扫描。
                if item.is_folder {
                    folder_queue.push_back(Some(item.id.clone()));
                    continue;
                }
                // 文件按“图片识别规则”过滤；凑够目标数量即可提前结束整个扫描。
                if is_gallery_image_item(&item) {
                    images.push(item);
                    if images.len() >= target {
                        break;
                    }
                }
            }

            if images.len() >= target {
                break;
            }

            next_link = page.next_link;
            page_count += 1;
            if next_link.is_none() || page_count >= ROOT_SCAN_MAX_PAGES_PER_FOLDER {
                break;
            }
        }
    }

    Ok(DrivePage {
        items: images,
        next_link: None,
    })
}

/// 为 root（或某个 folder）构造 `children` 列表请求 URL，并附带缩略图查询与 `$top`。
///
/// - `folder_id = None`：请求 `drive/root/children`
/// - `folder_id = Some(id)`：请求 `drive/items/{id}/children`
fn build_children_url_for_folder(folder_id: Option<&str>) -> String {
    match folder_id.map(str::trim).filter(|v| !v.is_empty()) {
        Some(id) => format!(
            "{GRAPH_BASE}/me/drive/items/{id}/children{THUMBNAIL_QUERY}&$top={ROOT_SCAN_PAGE_TOP}"
        ),
        None => format!(
            "{GRAPH_BASE}/me/drive/root/children{THUMBNAIL_QUERY}&$top={ROOT_SCAN_PAGE_TOP}"
        ),
    }
}

/// 判断一个 `DriveItemSummary` 是否应被视为“图库图片条目”。
///
/// 规则（按优先级）：
/// 1. 文件夹永远不是图片条目；
/// 2. `mime_type` 存在时优先使用：
///    - `image/*` 视为图片
///    - `video/*` 明确排除（即使扩展名看起来像图片也不算）
/// 3. `mime_type` 缺失或无法判断时，使用扩展名兜底（不区分大小写）。
fn is_gallery_image_item(item: &DriveItemSummary) -> bool {
    if item.is_folder {
        return false;
    }

    if let Some(mime) = item.mime_type.as_deref() {
        let normalized = mime.trim().to_ascii_lowercase();
        if normalized.starts_with("image/") {
            return true;
        }
        if normalized.starts_with("video/") {
            return false;
        }
    }

    has_image_extension(&item.name)
}

/// 扩展名兜底判断：根据文件名后缀判断是否为常见图片格式。
///
/// 注意：
/// - 这里的判断是“启发式”的，只用于 `mime_type` 不可用时的兜底；
/// - 取最后一个 `.` 之后的部分作为扩展名，忽略大小写与两侧空白；
/// - 未列入白名单的格式一律返回 `false`（宁可漏判，也不误判成图片）。
fn has_image_extension(name: &str) -> bool {
    let ext = name
        .rsplit_once('.')
        .map(|(_, ext)| ext.trim().to_ascii_lowercase());
    let Some(ext) = ext else {
        return false;
    };

    matches!(
        ext.as_str(),
        "jpg"
            | "jpeg"
            | "png"
            | "gif"
            | "webp"
            | "bmp"
            | "heic"
            | "heif"
            | "avif"
            | "tif"
            | "tiff"
            | "raw"
            | "dng"
            | "arw"
            | "cr2"
            | "cr3"
            | "nef"
            | "raf"
            | "rw2"
            | "orf"
    )
}

#[cfg(test)]
mod tests {
    use super::{build_children_url_for_folder, build_gallery_children_url, is_gallery_image_item};
    use crate::api::drive::models::DriveItemSummary;

    fn build_item(name: &str, mime_type: Option<&str>, is_folder: bool) -> DriveItemSummary {
        DriveItemSummary {
            id: "id".to_string(),
            name: name.to_string(),
            size: Some(1024),
            is_folder,
            child_count: None,
            mime_type: mime_type.map(|v| v.to_string()),
            last_modified: None,
            thumbnail_url: None,
        }
    }

    #[test]
    fn build_gallery_children_url_applies_default_top() {
        let url = build_gallery_children_url(None);
        assert!(url.contains("/me/drive/special/photos/children?"));
        assert!(url.contains("&$top=120"));
    }

    #[test]
    fn build_gallery_children_url_overrides_top() {
        let url = build_gallery_children_url(Some(48));
        assert!(url.contains("&$top=48"));
    }

    #[test]
    fn image_item_detection_prefers_mime() {
        let image = build_item("clip.mp4", Some("image/webp"), false);
        let video = build_item("photo.jpg", Some("video/mp4"), false);
        assert!(is_gallery_image_item(&image));
        assert!(!is_gallery_image_item(&video));
    }

    #[test]
    fn image_item_detection_uses_extension_fallback() {
        let image = build_item("camera_roll.HEIC", None, false);
        let other = build_item("archive.zip", None, false);
        assert!(is_gallery_image_item(&image));
        assert!(!is_gallery_image_item(&other));
    }

    #[test]
    fn folders_are_not_gallery_items() {
        let folder = build_item("Album", Some("image/jpeg"), true);
        assert!(!is_gallery_image_item(&folder));
    }

    #[test]
    fn build_children_url_for_folder_uses_root_when_missing_id() {
        let url = build_children_url_for_folder(None);
        assert!(url.contains("/me/drive/root/children?"));
        assert!(url.contains("&$top=200"));
    }

    #[test]
    fn build_children_url_for_folder_uses_item_children_for_folder_id() {
        let url = build_children_url_for_folder(Some("folder-123"));
        assert!(url.contains("/me/drive/items/folder-123/children?"));
        assert!(url.contains("&$top=200"));
    }
}
