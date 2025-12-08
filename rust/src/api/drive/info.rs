use super::{
    client::{build_blocking_client, current_access_token},
    models::{DriveInfo, DriveOwner, DriveQuota},
    GRAPH_BASE,
};
use serde::Deserialize;
use std::time::Duration;

/// 获取当前用户的 OneDrive 概览信息（包含配额与所有者）。
/// - 请求：`GET /me/drive?$select=id,driveType,owner,quota`
/// - 若 OneDrive 未开通或不可用，返回明确的错误提示。
#[flutter_rust_bridge::frb]
pub fn get_drive_overview() -> Result<DriveInfo, String> {
    let access_token = current_access_token()?;
    let client = build_blocking_client(Duration::from_secs(30))?;

    let url = format!("{GRAPH_BASE}/me/drive?$select=id,driveType,owner,quota");
    let response = client
        .get(url)
        .bearer_auth(&access_token)
        .header("Accept", "application/json")
        .send()
        .map_err(|e| format!("failed to fetch drive overview: {e}"))?;

    if response.status().as_u16() == 401 {
        return Err("access token rejected by Graph API; please sign in again".to_string());
    }
    if response.status().as_u16() == 404 {
        return Err("OneDrive 不存在或尚未开通，请确认账号状态后重试".to_string());
    }
    if !response.status().is_success() {
        return Err(format!(
            "graph api returned HTTP {} while fetching drive overview",
            response.status()
        ));
    }

    let payload: DriveInfoDto = response
        .json()
        .map_err(|e| format!("failed to parse drive overview: {e}"))?;

    Ok(DriveInfo {
        id: payload.id,
        drive_type: payload.drive_type,
        owner: payload.owner.and_then(DriveOwner::from_identity_set),
        quota: payload.quota.map(DriveQuota::from),
    })
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DriveInfoDto {
    id: Option<String>,
    #[serde(rename = "driveType")]
    drive_type: Option<String>,
    owner: Option<IdentitySetDto>,
    quota: Option<DriveQuotaDto>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct IdentitySetDto {
    user: Option<IdentityDto>,
    group: Option<IdentityDto>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct IdentityDto {
    id: Option<String>,
    display_name: Option<String>,
    user_principal_name: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DriveQuotaDto {
    total: Option<u64>,
    used: Option<u64>,
    remaining: Option<u64>,
    deleted: Option<u64>,
    state: Option<String>,
}

impl DriveOwner {
    /// 按优先级选择 user/group，保持字段为原始值。
    fn from_identity_set(set: IdentitySetDto) -> Option<Self> {
        let identity = set.user.or(set.group)?;
        Some(DriveOwner {
            display_name: identity.display_name,
            user_principal_name: identity.user_principal_name,
            id: identity.id,
        })
    }
}

impl From<DriveQuotaDto> for DriveQuota {
    fn from(value: DriveQuotaDto) -> Self {
        DriveQuota {
            total: value.total,
            used: value.used,
            remaining: value.remaining,
            deleted: value.deleted,
            state: value.state,
        }
    }
}
