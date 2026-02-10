use super::{
    list::{fetch_drive_page, THUMBNAIL_QUERY},
    models::DrivePage,
    GRAPH_BASE,
};
use percent_encoding::{utf8_percent_encode, NON_ALPHANUMERIC};

/// 在 OneDrive 中执行远程搜索。
/// - `folder_id` 为空时，从 root 作为搜索范围。
/// - `next_link` 优先级最高，用于分页续取。
#[flutter_rust_bridge::frb]
pub fn search_drive_items(
    query: String,
    folder_id: Option<String>,
    next_link: Option<String>,
    top: Option<u32>,
) -> Result<DrivePage, String> {
    if let Some(link) = next_link {
        return fetch_drive_page(&link);
    }

    let trimmed = query.trim();
    if trimmed.is_empty() {
        return Err("search query is required".to_string());
    }

    let request_url = build_search_url(trimmed, folder_id.as_deref(), top);
    fetch_drive_page(&request_url)
}

fn build_search_url(query: &str, folder_id: Option<&str>, top: Option<u32>) -> String {
    // OData 字符串字面量中的单引号需要转义成两个单引号。
    let escaped_query = query.replace('\'', "''");
    let encoded_query = utf8_percent_encode(&escaped_query, NON_ALPHANUMERIC).to_string();

    let base = match folder_id.map(str::trim).filter(|v| !v.is_empty()) {
        Some(id) => format!("{GRAPH_BASE}/me/drive/items/{id}/search(q='{encoded_query}')"),
        None => format!("{GRAPH_BASE}/me/drive/root/search(q='{encoded_query}')"),
    };

    let mut url = format!("{base}{THUMBNAIL_QUERY}");
    if let Some(value) = top.filter(|v| *v > 0) {
        url.push_str(&format!("&$top={value}"));
    }
    url
}

#[cfg(test)]
mod tests {
    use super::build_search_url;

    #[test]
    fn build_search_url_uses_root_scope_when_folder_missing() {
        let url = build_search_url("project plan", None, None);
        assert!(url.contains("/me/drive/root/search(q='project%20plan')?"));
        assert!(url.contains("$select=id,name,size,lastModifiedDateTime,folder,file"));
    }

    #[test]
    fn build_search_url_escapes_apostrophe_and_applies_top() {
        let url = build_search_url("Bob's notes", Some("folder-123"), Some(25));
        assert!(url.contains("/me/drive/items/folder-123/search(q='Bob%27%27s%20notes')?"));
        assert!(url.contains("&$top=25"));
    }
}
