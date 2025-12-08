use super::{
    client::{build_blocking_client, current_access_token},
    info::get_drive_overview,
    models::{LinkScope, LinkType, ShareCapabilities, ShareLinkResult},
    GRAPH_BASE,
};
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// 读取当前账户的分享能力，便于前端灰掉不支持的选项。
#[flutter_rust_bridge::frb]
pub fn get_share_capabilities() -> Result<ShareCapabilities, String> {
    let overview = get_drive_overview()?;
    let drive_type = overview.drive_type.clone().unwrap_or_default();
    let caps = ShareCapabilities::from_drive_type(drive_type.as_str());
    Ok(caps)
}

/// 为指定 item 创建分享链接（支持个人/企业差异）。
#[flutter_rust_bridge::frb]
pub fn create_share_link(
    item_id: String,
    link_type: LinkType,
    scope: LinkScope,
    password: Option<String>,
    expiration_date_time: Option<String>,
    retain_inherited_permissions: Option<bool>,
    recipients: Option<Vec<String>>,
) -> Result<ShareLinkResult, String> {
    if item_id.trim().is_empty() {
        return Err("drive item id is required".to_string());
    }

    let overview = get_drive_overview()?;
    let drive_type = overview.drive_type.unwrap_or_default();
    let caps = ShareCapabilities::from_drive_type(drive_type.as_str());

    if matches!(link_type, LinkType::Embed) && !caps.can_embed_link {
        return Err("当前账户类型不支持嵌入链接（embed）".to_string());
    }
    if matches!(scope, LinkScope::Organization) && !caps.can_org_scope_link {
        return Err("当前账户类型不支持组织内链接".to_string());
    }
    if password.as_ref().map(|p| p.is_empty()).unwrap_or(false) {
        return Err("密码不能为空字符串".to_string());
    }
    if password.is_some() && !caps.can_password {
        return Err("仅个人版 OneDrive 支持密码保护链接".to_string());
    }
    if matches!(scope, LinkScope::Users) {
        if recipients.as_ref().map(|r| r.is_empty()).unwrap_or(true) {
            return Err("指定人员链接需要提供至少一个收件人".to_string());
        }
    } else if recipients.is_some() {
        return Err("只有 scope=users 时才允许指定收件人".to_string());
    }

    let body = CreateLinkRequest::new(
        link_type.clone(),
        scope.clone(),
        password,
        expiration_date_time,
        retain_inherited_permissions,
        recipients,
    );

    let access_token = current_access_token()?;
    let client = build_blocking_client(Duration::from_secs(30))?;
    let url = format!("{GRAPH_BASE}/me/drive/items/{item_id}/createLink");
    let response = client
        .post(url)
        .bearer_auth(&access_token)
        .header("Accept", "application/json")
        .json(&body)
        .send()
        .map_err(|e| format!("failed to create share link: {e}"))?;

    eprintln!(
        "[share] createLink request body: type={:?} scope={:?} pwd_set={} recipients={:?} retain_inherited={:?} expiration={:?}",
        link_type,
        scope,
        body.password.as_ref().map(|p| !p.is_empty()).unwrap_or(false),
        body.recipients.as_ref().map(|list| list.len()),
        body.retain_inherited_permissions,
        body.expiration_date_time
    );

    if response.status().as_u16() == 401 {
        return Err("access token rejected by Graph API; please sign in again".to_string());
    }
    if response.status().as_u16() == 404 {
        return Err("未找到指定的项目，可能已被移动或删除".to_string());
    }
    if response.status().as_u16() == 403 {
        return Err("Graph API 拒绝了分享请求，可能已被租户策略禁用".to_string());
    }
    eprintln!(
        "[share] createLink response status: {}",
        response.status()
    );
    if !response.status().is_success() {
        return Err(format!(
            "graph api returned HTTP {} while creating share link",
            response.status()
        ));
    }

    let raw = response
        .text()
        .map_err(|e| format!("failed to read createLink response body: {e}"))?;
    eprintln!("[share] createLink raw response: {raw}");

    let payload: PermissionDto =
        serde_json::from_str(&raw).map_err(|e| format!("failed to parse createLink response: {e}"))?;

    ShareLinkResult::try_from(payload)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CreateLinkRequest {
    #[serde(rename = "type")]
    link_type: String,
    scope: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    password: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    expiration_date_time: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    retain_inherited_permissions: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    recipients: Option<Vec<RecipientDto>>,
}

impl CreateLinkRequest {
    fn new(
        link_type: LinkType,
        scope: LinkScope,
        password: Option<String>,
        expiration_date_time: Option<String>,
        retain_inherited_permissions: Option<bool>,
        recipients: Option<Vec<String>>,
    ) -> Self {
        let recipients = recipients.map(|items| {
            items
                .into_iter()
                .filter(|email| !email.trim().is_empty())
                .map(|email| RecipientDto {
                    email: email.trim().to_string(),
                })
                .collect::<Vec<_>>()
        });

        CreateLinkRequest {
            link_type: link_type.as_graph_str().to_string(),
            scope: scope.as_graph_str().to_string(),
            password,
            expiration_date_time,
            retain_inherited_permissions,
            recipients,
        }
    }
}

#[derive(Debug, Serialize)]
struct RecipientDto {
    email: String,
}

#[derive(Debug, Deserialize)]
struct PermissionDto {
    id: Option<String>,
    roles: Option<Vec<String>>,
    share_id: Option<String>,
    has_password: Option<bool>,
    link: Option<LinkDto>,
}

#[derive(Debug, Deserialize)]
struct LinkDto {
    #[serde(rename = "type")]
    link_type: Option<String>,
    scope: Option<String>,
    #[serde(rename = "webUrl")]
    web_url: Option<String>,
    #[serde(rename = "webHtml")]
    web_html: Option<String>,
}

impl ShareCapabilities {
    fn from_drive_type(drive_type: &str) -> Self {
        let is_personal = drive_type.eq_ignore_ascii_case("personal");
        ShareCapabilities {
            drive_type: Some(drive_type.to_string()),
            can_embed_link: is_personal,
            can_org_scope_link: !is_personal,
            can_password: is_personal,
        }
    }
}

impl LinkType {
    fn as_graph_str(&self) -> &'static str {
        match self {
            LinkType::View => "view",
            LinkType::Edit => "edit",
            LinkType::Embed => "embed",
        }
    }

    fn from_graph_str(value: &str) -> Option<Self> {
        match value {
            "view" => Some(LinkType::View),
            "edit" => Some(LinkType::Edit),
            "embed" => Some(LinkType::Embed),
            _ => None,
        }
    }
}

impl LinkScope {
    fn as_graph_str(&self) -> &'static str {
        match self {
            LinkScope::Anonymous => "anonymous",
            LinkScope::Organization => "organization",
            LinkScope::Users => "users",
        }
    }

    fn from_graph_str(value: &str) -> Option<Self> {
        match value {
            "anonymous" => Some(LinkScope::Anonymous),
            "organization" => Some(LinkScope::Organization),
            "users" => Some(LinkScope::Users),
            _ => None,
        }
    }
}

impl TryFrom<PermissionDto> for ShareLinkResult {
    type Error = String;

    fn try_from(value: PermissionDto) -> Result<Self, Self::Error> {
        let link = value
            .link
            .ok_or_else(|| "missing link object in createLink response".to_string())?;
        let link_type = link
            .link_type
            .as_deref()
            .and_then(LinkType::from_graph_str)
            .ok_or_else(|| "unexpected link type in response".to_string())?;
        let scope = link
            .scope
            .as_deref()
            .and_then(LinkScope::from_graph_str)
            .ok_or_else(|| "unexpected scope in response".to_string())?;
        let url = link.web_url.clone();
        let html = link.web_html.clone();
        // 直接透传 raw 字段，即使 webUrl 为空也返回，由上层决定提示。

        Ok(ShareLinkResult {
            link_type,
            scope,
            web_url: url,
            web_html: html,
            permission_id: value.id,
            share_id: value.share_id,
            roles: value.roles.unwrap_or_default(),
            password_protected: value.has_password.unwrap_or(false),
        })
    }
}
