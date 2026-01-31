use crate::db::{self, AuthAccountRecord};
use std::io::{Read, Write};
use std::net::TcpListener;
use std::time::Duration;

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use rand::{distr::Alphanumeric, Rng};
use reqwest::blocking::Client;
use serde::Deserialize;
use serde_json::from_slice as from_json_slice;
use sha2::{Digest, Sha256};
use url::Url;
use uuid::Uuid;

pub(super) const AUTHORITY: &str = "https://login.microsoftonline.com/common/oauth2/v2.0";
const AUTHORIZE_PATH: &str = "authorize";
pub(super) const TOKEN_PATH: &str = "token";
const ACTIVE_ACCOUNT_KEY: &str = "active_account_id";

#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct AuthTokens {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_in: Option<u64>,
    pub id_token: Option<String>,
    pub scope: Option<String>,
    pub token_type: Option<String>,
}

#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct StoredAuthState {
    pub account_id: String,
    pub client_id: String,
    pub tokens: AuthTokens,
    pub updated_at_millis: i64,
}

#[flutter_rust_bridge::frb]
#[derive(Clone, Debug)]
pub struct AuthAccount {
    pub account_id: String,
    pub client_id: String,
    pub display_name: Option<String>,
    pub user_principal_name: Option<String>,
    pub updated_at_millis: i64,
    pub is_active: bool,
}

impl From<AuthAccountRecord> for StoredAuthState {
    fn from(record: AuthAccountRecord) -> Self {
        StoredAuthState {
            account_id: record.account_id,
            client_id: record.client_id,
            tokens: AuthTokens {
                access_token: record.access_token,
                refresh_token: record.refresh_token,
                expires_in: convert_expires_in(record.expires_in_seconds),
                id_token: record.id_token,
                scope: record.scope,
                token_type: record.token_type,
            },
            updated_at_millis: record.updated_at_millis,
        }
    }
}

#[derive(Debug, Deserialize)]
pub(super) struct TokenResponse {
    pub(super) access_token: Option<String>,
    pub(super) refresh_token: Option<String>,
    pub(super) expires_in: Option<u64>,
    pub(super) id_token: Option<String>,
    pub(super) scope: Option<String>,
    pub(super) token_type: Option<String>,
    pub(super) error: Option<String>,
    pub(super) error_description: Option<String>,
}

#[derive(Debug, Deserialize)]
struct IdTokenClaims {
    oid: Option<String>,
    sub: Option<String>,
    tid: Option<String>,
    name: Option<String>,
    preferred_username: Option<String>,
    upn: Option<String>,
    email: Option<String>,
}

#[derive(Debug)]
struct AccountIdentity {
    account_id: String,
    display_name: Option<String>,
    user_principal_name: Option<String>,
}

#[flutter_rust_bridge::frb]
pub fn authenticate_via_browser(
    client_id: String,
    scopes: Vec<String>,
) -> Result<AuthTokens, String> {
    let scopes = normalize_scopes(scopes);
    let scope_param = scopes.join(" ");
    let code_verifier = build_code_verifier();
    let code_challenge = build_code_challenge(&code_verifier)?;
    let state = random_string(32);

    let listener = TcpListener::bind(("127.0.0.1", 0))
        .map_err(|e| format!("failed to bind redirect listener: {e}"))?;
    listener
        .set_nonblocking(false)
        .map_err(|e| format!("failed to configure listener: {e}"))?;
    let redirect_port = listener
        .local_addr()
        .map_err(|e| format!("failed to read redirect listener port: {e}"))?
        .port();
    let redirect_uri = format!("http://localhost:{redirect_port}");

    let authorize_url = build_authorize_url(
        &client_id,
        &scope_param,
        &redirect_uri,
        &code_challenge,
        &state,
    )?;

    webbrowser::open(&authorize_url).map_err(|e| format!("failed to open browser: {e}"))?;

    let (code, received_state) = wait_for_code(listener)?;
    if received_state.as_deref() != Some(&state) {
        return Err("state mismatch in authorization response".to_string());
    }

    exchange_code_for_tokens(
        &client_id,
        &scope_param,
        &redirect_uri,
        &code_verifier,
        &code,
    )
}

fn normalize_scopes(mut scopes: Vec<String>) -> Vec<String> {
    if scopes.is_empty() {
        scopes.push("User.Read".to_string());
    }
    if !scopes.iter().any(|s| s == "offline_access") {
        scopes.push("offline_access".to_string());
    }
    if !scopes.iter().any(|s| s == "openid") {
        scopes.push("openid".to_string());
    }
    scopes
}

fn build_authorize_url(
    client_id: &str,
    scope: &str,
    redirect_uri: &str,
    code_challenge: &str,
    state: &str,
) -> Result<String, String> {
    let mut url = Url::parse(&format!("{AUTHORITY}/{AUTHORIZE_PATH}"))
        .map_err(|e| format!("failed to parse authorize endpoint: {e}"))?;
    url.query_pairs_mut()
        .append_pair("client_id", client_id)
        .append_pair("response_type", "code")
        .append_pair("response_mode", "query")
        .append_pair("redirect_uri", redirect_uri)
        .append_pair("scope", scope)
        .append_pair("code_challenge", code_challenge)
        .append_pair("code_challenge_method", "S256")
        .append_pair("state", state);
    Ok(url.into())
}

fn exchange_code_for_tokens(
    client_id: &str,
    scope: &str,
    redirect_uri: &str,
    code_verifier: &str,
    code: &str,
) -> Result<AuthTokens, String> {
    let mut params = vec![
        ("client_id", client_id.to_string()),
        ("grant_type", "authorization_code".to_string()),
        ("code", code.to_string()),
        ("redirect_uri", redirect_uri.to_string()),
        ("code_verifier", code_verifier.to_string()),
    ];
    if !scope.is_empty() {
        params.push(("scope", scope.to_string()));
    }

    let client = Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|e| format!("failed to build HTTP client: {e}"))?;

    let token_url = format!("{AUTHORITY}/{TOKEN_PATH}");
    let response = client
        .post(token_url)
        .form(&params)
        .send()
        .map_err(|e| format!("token exchange failed: {e}"))?;

    if !response.status().is_success() {
        return Err(format!(
            "token endpoint returned HTTP {}",
            response.status()
        ));
    }

    let payload: TokenResponse = response
        .json()
        .map_err(|e| format!("failed to parse token response: {e}"))?;

    if let Some(error) = payload.error {
        let description = payload.error_description.unwrap_or_default();
        return Err(format!("{error}: {description}"));
    }

    let access_token = payload
        .access_token
        .ok_or_else(|| "missing access_token in response".to_string())?;

    let tokens = AuthTokens {
        access_token,
        refresh_token: payload.refresh_token,
        expires_in: payload.expires_in,
        id_token: payload.id_token,
        scope: payload.scope,
        token_type: payload.token_type,
    };

    if let Err(err) = persist_tokens(&client_id, &tokens) {
        eprintln!("failed to persist auth tokens: {err}");
    }

    Ok(tokens)
}

#[flutter_rust_bridge::frb]
pub fn persist_auth_state(client_id: String, tokens: AuthTokens) -> Result<(), String> {
    persist_tokens(&client_id, &tokens).map(|_| ())
}

#[flutter_rust_bridge::frb]
pub fn load_persisted_auth_state() -> Result<Option<StoredAuthState>, String> {
    if let Some(record) = resolve_active_auth_record()? {
        return Ok(Some(StoredAuthState::from(record)));
    }
    if let Some(migrated) = migrate_legacy_auth_record()? {
        return Ok(Some(migrated));
    }
    Ok(None)
}

#[flutter_rust_bridge::frb]
pub fn list_auth_accounts() -> Result<Vec<AuthAccount>, String> {
    let records = db::list_auth_accounts()?;
    let mut active_id = get_active_account_id()?;
    let has_active = active_id
        .as_ref()
        .map(|id| records.iter().any(|record| record.account_id == *id))
        .unwrap_or(false);
    if !has_active {
        if let Some(record) = records.first() {
            set_active_account_id(Some(&record.account_id))?;
            active_id = Some(record.account_id.clone());
        } else {
            set_active_account_id(None)?;
            active_id = None;
        }
    }
    let active_ref = active_id.as_deref();
    Ok(records
        .into_iter()
        .map(|record| {
            let account_id = record.account_id;
            let is_active = active_ref == Some(account_id.as_str());
            AuthAccount {
                account_id,
                client_id: record.client_id,
                display_name: record.display_name,
                user_principal_name: record.user_principal_name,
                updated_at_millis: record.updated_at_millis,
                is_active,
            }
        })
        .collect())
}

#[flutter_rust_bridge::frb]
pub fn set_active_auth_account(account_id: String) -> Result<StoredAuthState, String> {
    let record = db::load_auth_account(&account_id)?
        .ok_or_else(|| "target account does not exist".to_string())?;
    set_active_account_id(Some(&record.account_id))?;
    Ok(StoredAuthState::from(record))
}

#[flutter_rust_bridge::frb]
pub fn remove_auth_account(account_id: String) -> Result<Option<StoredAuthState>, String> {
    let active_id = get_active_account_id()?;
    db::delete_auth_account(&account_id)?;
    if active_id.as_deref() == Some(&account_id) {
        let records = db::list_auth_accounts()?;
        if let Some(next) = records.first() {
            set_active_account_id(Some(&next.account_id))?;
            return Ok(Some(StoredAuthState::from(next.clone())));
        }
        set_active_account_id(None)?;
        return Ok(None);
    }
    Ok(None)
}

#[flutter_rust_bridge::frb]
pub fn update_auth_account_profile(
    account_id: String,
    display_name: Option<String>,
    user_principal_name: Option<String>,
) -> Result<(), String> {
    let name = normalize_optional(display_name);
    let upn = normalize_optional(user_principal_name);
    db::update_auth_account_profile(&account_id, name.as_deref(), upn.as_deref())?;
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn clear_persisted_auth_state() -> Result<(), String> {
    db::clear_auth_accounts()?;
    db::clear_legacy_auth_record()?;
    set_active_account_id(None)
}

fn wait_for_code(listener: TcpListener) -> Result<(String, Option<String>), String> {
    let (mut stream, _) = listener
        .accept()
        .map_err(|e| format!("failed to receive redirect: {e}"))?;

    let mut buffer = [0_u8; 4096];
    let read = stream
        .read(&mut buffer)
        .map_err(|e| format!("failed to read redirect: {e}"))?;
    let request = String::from_utf8_lossy(&buffer[..read]);
    let path = request
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .ok_or_else(|| "failed to parse HTTP request line".to_string())?;

    let redirect_url = Url::parse(&format!("http://localhost{path}"))
        .map_err(|e| format!("failed to parse redirect url: {e}"))?;
    let mut code: Option<String> = None;
    let mut state: Option<String> = None;

    for (key, value) in redirect_url.query_pairs() {
        match key.as_ref() {
            "code" => code = Some(value.into_owned()),
            "state" => state = Some(value.into_owned()),
            "error" => {
                send_browser_response(
                    &mut stream,
                    "Authentication Failed",
                    "We were unable to complete sign-in. You can close this window.",
                )?;
                return Err(format!("authorization error: {}", value));
            }
            _ => {}
        }
    }

    let code = code.ok_or_else(|| "authorization code missing in redirect".to_string())?;

    send_browser_response(
        &mut stream,
        "Authentication Complete",
        "You can return to the Skydrivex app.",
    )?;

    Ok((code, state))
}

fn send_browser_response(
    stream: &mut std::net::TcpStream,
    title: &str,
    message: &str,
) -> Result<(), String> {
    let body = format!(
        "<html><head><meta charset=\"utf-8\"><title>{title}</title></head>\
         <body><h1>{title}</h1><p>{message}</p></body></html>"
    );
    let response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    stream
        .write_all(response.as_bytes())
        .map_err(|e| format!("failed to send browser response: {e}"))
}

fn build_code_verifier() -> String {
    rand::rng()
        .sample_iter(&Alphanumeric)
        .take(64)
        .map(char::from)
        .collect()
}

fn build_code_challenge(code_verifier: &str) -> Result<String, String> {
    let digest = Sha256::digest(code_verifier.as_bytes());
    Ok(URL_SAFE_NO_PAD.encode(digest))
}

fn random_string(len: usize) -> String {
    rand::rng()
        .sample_iter(&Alphanumeric)
        .take(len)
        .map(char::from)
        .collect()
}

fn get_active_account_id() -> Result<Option<String>, String> {
    let stored = db::get_setting(ACTIVE_ACCOUNT_KEY)?;
    Ok(stored.and_then(|value| {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    }))
}

fn set_active_account_id(account_id: Option<&str>) -> Result<(), String> {
    match account_id {
        Some(value) => db::set_setting(ACTIVE_ACCOUNT_KEY, value),
        None => db::set_setting(ACTIVE_ACCOUNT_KEY, ""),
    }
}

fn resolve_active_auth_record() -> Result<Option<AuthAccountRecord>, String> {
    if let Some(active_id) = get_active_account_id()? {
        if let Some(record) = db::load_auth_account(&active_id)? {
            return Ok(Some(record));
        }
    }
    let records = db::list_auth_accounts()?;
    if let Some(record) = records.first() {
        set_active_account_id(Some(&record.account_id))?;
        return Ok(Some(record.clone()));
    }
    Ok(None)
}

pub(crate) fn load_active_auth_record() -> Result<AuthAccountRecord, String> {
    if let Some(record) = resolve_active_auth_record()? {
        return Ok(record);
    }
    if migrate_legacy_auth_record()?.is_some() {
        if let Some(record) = resolve_active_auth_record()? {
            return Ok(record);
        }
    }
    Err("no authentication state available; please sign in".to_string())
}

fn migrate_legacy_auth_record() -> Result<Option<StoredAuthState>, String> {
    let legacy = db::load_legacy_auth_record()?;
    let record = match legacy {
        Some(record) => record,
        None => return Ok(None),
    };
    let tokens = AuthTokens {
        access_token: record.access_token,
        refresh_token: record.refresh_token,
        expires_in: convert_expires_in(record.expires_in_seconds),
        id_token: record.id_token,
        scope: record.scope,
        token_type: record.token_type,
    };
    let state = persist_tokens(&record.client_id, &tokens)?;
    db::clear_legacy_auth_record()?;
    Ok(Some(state))
}

pub(super) fn persist_tokens(
    client_id: &str,
    tokens: &AuthTokens,
) -> Result<StoredAuthState, String> {
    let identity = resolve_account_identity(tokens);
    persist_tokens_for_account(
        &identity.account_id,
        client_id,
        tokens,
        identity.display_name,
        identity.user_principal_name,
    )
}

pub(super) fn persist_tokens_for_account(
    account_id: &str,
    client_id: &str,
    tokens: &AuthTokens,
    display_name: Option<String>,
    user_principal_name: Option<String>,
) -> Result<StoredAuthState, String> {
    let record = record_from_tokens(
        account_id,
        client_id,
        tokens,
        display_name,
        user_principal_name,
    );
    db::upsert_auth_account(&record)?;
    set_active_account_id(Some(&record.account_id))?;
    Ok(StoredAuthState::from(record))
}

pub(super) fn record_from_tokens(
    account_id: &str,
    client_id: &str,
    tokens: &AuthTokens,
    display_name: Option<String>,
    user_principal_name: Option<String>,
) -> AuthAccountRecord {
    let identity = resolve_account_identity(tokens);
    db::build_account_record(
        account_id.to_string(),
        client_id.to_string(),
        tokens.access_token.clone(),
        tokens.refresh_token.clone(),
        tokens.expires_in,
        tokens.id_token.clone(),
        tokens.scope.clone(),
        tokens.token_type.clone(),
        display_name.or(identity.display_name),
        user_principal_name.or(identity.user_principal_name),
    )
}

fn convert_expires_in(value: Option<i64>) -> Option<u64> {
    value.and_then(|v| if v < 0 { None } else { Some(v as u64) })
}

fn resolve_account_identity(tokens: &AuthTokens) -> AccountIdentity {
    if let Some(id_token) = tokens.id_token.as_deref() {
        if let Some(claims) = decode_id_token(id_token) {
            let account_id = account_id_from_claims(&claims);
            let display_name = claims.name.clone();
            let user_principal_name = claims
                .preferred_username
                .clone()
                .or(claims.upn.clone())
                .or(claims.email.clone());
            if let Some(account_id) = account_id {
                return AccountIdentity {
                    account_id,
                    display_name,
                    user_principal_name,
                };
            }
        }
    }
    AccountIdentity {
        account_id: Uuid::new_v4().to_string(),
        display_name: None,
        user_principal_name: None,
    }
}

fn normalize_optional(value: Option<String>) -> Option<String> {
    value.and_then(|raw| {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    })
}

fn decode_id_token(id_token: &str) -> Option<IdTokenClaims> {
    let mut parts = id_token.split('.');
    let _header = parts.next()?;
    let payload = parts.next()?;
    let decoded = URL_SAFE_NO_PAD.decode(payload.as_bytes()).ok()?;
    from_json_slice(&decoded).ok()
}

fn account_id_from_claims(claims: &IdTokenClaims) -> Option<String> {
    if let (Some(tid), Some(oid)) = (claims.tid.as_ref(), claims.oid.as_ref()) {
        return Some(format!("{tid}:{oid}"));
    }
    if let Some(oid) = claims.oid.as_ref() {
        return Some(oid.clone());
    }
    if let (Some(tid), Some(sub)) = (claims.tid.as_ref(), claims.sub.as_ref()) {
        return Some(format!("{tid}:{sub}"));
    }
    if let Some(sub) = claims.sub.as_ref() {
        return Some(sub.clone());
    }
    if let Some(username) = claims.preferred_username.as_ref() {
        return Some(username.clone());
    }
    if let Some(upn) = claims.upn.as_ref() {
        return Some(upn.clone());
    }
    claims.email.as_ref().cloned()
}
