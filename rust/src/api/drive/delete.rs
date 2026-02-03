use super::{
    client::{build_blocking_client, send_with_refresh},
    GRAPH_BASE,
};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
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

    let client = build_blocking_client(Duration::from_secs(30))?;
    let url = format!("{GRAPH_BASE}/me/drive/items/{item_id}");

    let if_match = if_match.filter(|t| !t.trim().is_empty());
    let response = send_with_refresh(|token| {
        let mut request = client
            .delete(&url)
            .bearer_auth(token)
            .header("Accept", "application/json");
        if let Some(tag) = if_match.as_deref() {
            request = request.header("If-Match", tag);
        }
        if bypass_locks {
            request = request.header("Prefer", "bypass-shared-lock,bypass-checked-out");
        }
        request
            .send()
            .map_err(|e| format!("failed to delete drive item: {e}"))
    })?;

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

/// 批量删除 drive items（移动到回收站），最多 20 项。
/// 返回删除失败的 item ids。
#[flutter_rust_bridge::frb]
pub fn delete_drive_items_batch(
    item_ids: Vec<String>,
    bypass_locks: bool,
) -> Result<Vec<String>, String> {
    if item_ids.is_empty() {
        return Ok(vec![]);
    }
    if item_ids.len() > 20 {
        return Err("batch delete supports up to 20 items".to_string());
    }

    let mut id_map: HashMap<String, String> = HashMap::new();
    let mut requests = Vec::with_capacity(item_ids.len());
    let prefer_value = "bypass-shared-lock,bypass-checked-out".to_string();
    for (index, item_id) in item_ids.iter().enumerate() {
        if item_id.trim().is_empty() {
            return Err("drive item id is required".to_string());
        }
        let request_id = (index + 1).to_string();
        id_map.insert(request_id.clone(), item_id.clone());
        let headers = if bypass_locks {
            let mut map = HashMap::new();
            map.insert("Prefer".to_string(), prefer_value.clone());
            Some(map)
        } else {
            None
        };
        requests.push(BatchDeleteRequest {
            id: request_id,
            method: "DELETE".to_string(),
            url: format!("/me/drive/items/{item_id}"),
            headers,
        });
    }

    let payload = BatchDeletePayload { requests };
    let client = build_blocking_client(Duration::from_secs(30))?;
    let url = format!("{GRAPH_BASE}/$batch");
    let response = send_with_refresh(|token| {
        client
            .post(&url)
            .bearer_auth(token)
            .header("Accept", "application/json")
            .json(&payload)
            .send()
            .map_err(|e| format!("failed to delete drive items batch: {e}"))
    })?;

    if response.status().as_u16() == 401 {
        return Err("access token rejected by Graph API; please sign in again".to_string());
    }
    if !response.status().is_success() {
        return Err(format!(
            "graph api returned HTTP {} when deleting items batch",
            response.status()
        ));
    }

    let payload: BatchDeleteResponsePayload = response
        .json()
        .map_err(|e| format!("failed to parse batch delete response: {e}"))?;
    let mut failures: HashSet<String> = HashSet::new();
    let mut responded_ids: HashSet<String> = HashSet::new();

    for entry in payload.responses {
        if let Some(item_id) = id_map.get(&entry.id) {
            responded_ids.insert(item_id.clone());
            if !entry.status.is_success() {
                failures.insert(item_id.clone());
            }
        }
    }

    for item_id in item_ids {
        if !responded_ids.contains(&item_id) {
            failures.insert(item_id);
        }
    }

    Ok(failures.into_iter().collect())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct BatchDeletePayload {
    requests: Vec<BatchDeleteRequest>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct BatchDeleteRequest {
    id: String,
    method: String,
    url: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    headers: Option<HashMap<String, String>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BatchDeleteResponsePayload {
    responses: Vec<BatchDeleteResponse>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BatchDeleteResponse {
    id: String,
    status: u16,
}

trait HttpStatusExt {
    fn is_success(self) -> bool;
}

impl HttpStatusExt for u16 {
    fn is_success(self) -> bool {
        (200..300).contains(&self)
    }
}
