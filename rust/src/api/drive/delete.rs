use super::{
    client::{build_blocking_client, current_access_token},
    GRAPH_BASE,
};
use std::time::Duration;

/// 删除指定的 drive item（移动到回收站），可选携带 If-Match 与 bypass 锁。
#[flutter_rust_bridge::frb]
pub fn delete_drive_item(
    item_id: String,
    if_match: Option<String>,
    bypass_locks: bool,
) -> Result<(), String> {
    if item_id.trim().is_empty() {
        return Err("drive item id is required".to_string());
    }

    let access_token = current_access_token()?;
    let client = build_blocking_client(Duration::from_secs(30))?;
    let url = format!("{GRAPH_BASE}/me/drive/items/{item_id}");

    let mut request = client
        .delete(url)
        .bearer_auth(&access_token)
        .header("Accept", "application/json");

    if let Some(tag) = if_match.filter(|t| !t.trim().is_empty()) {
        request = request.header("If-Match", tag);
    }
    if bypass_locks {
        request = request.header("Prefer", "bypass-shared-lock,bypass-checked-out");
    }

    let response = request
        .send()
        .map_err(|e| format!("failed to delete drive item: {e}"))?;

    let status = response.status();
    if status.as_u16() == 401 {
        return Err("access token rejected by Graph API; please sign in again".to_string());
    }
    if status.as_u16() == 404 {
        return Err("找不到要删除的项目，可能已被移动或无权限".to_string());
    }
    if status.as_u16() == 412 {
        return Err("删除被拒绝：ETag 不匹配或被共享锁占用".to_string());
    }
    if !status.is_success() {
        return Err(format!(
            "graph api returned HTTP {} when deleting item",
            status
        ));
    }

    Ok(())
}
