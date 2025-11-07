use crate::db::{self, AuthTokenRecord};
use std::io::{Read, Write};
use std::net::TcpListener;
use std::time::Duration;

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use rand::{distributions::Alphanumeric, Rng};
use reqwest::blocking::Client;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use url::Url;

const AUTHORITY: &str = "https://login.microsoftonline.com/common/oauth2/v2.0";
const AUTHORIZE_PATH: &str = "authorize";
const TOKEN_PATH: &str = "token";

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
    pub client_id: String,
    pub tokens: AuthTokens,
    pub updated_at_millis: i64,
}

impl From<AuthTokenRecord> for StoredAuthState {
    fn from(record: AuthTokenRecord) -> Self {
        StoredAuthState {
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
struct TokenResponse {
    access_token: Option<String>,
    refresh_token: Option<String>,
    expires_in: Option<u64>,
    id_token: Option<String>,
    scope: Option<String>,
    token_type: Option<String>,
    error: Option<String>,
    error_description: Option<String>,
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
    persist_tokens(&client_id, &tokens)
}

#[flutter_rust_bridge::frb]
pub fn load_persisted_auth_state() -> Result<Option<StoredAuthState>, String> {
    db::load_auth_record().map(|record| record.map(StoredAuthState::from))
}

#[flutter_rust_bridge::frb]
pub fn clear_persisted_auth_state() -> Result<(), String> {
    db::clear_auth_record()
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
    rand::thread_rng()
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
    rand::thread_rng()
        .sample_iter(&Alphanumeric)
        .take(len)
        .map(char::from)
        .collect()
}

fn persist_tokens(client_id: &str, tokens: &AuthTokens) -> Result<(), String> {
    let record = record_from_tokens(client_id, tokens);
    db::upsert_auth_record(&record)
}

fn record_from_tokens(client_id: &str, tokens: &AuthTokens) -> AuthTokenRecord {
    db::build_record(
        client_id.to_string(),
        tokens.access_token.clone(),
        tokens.refresh_token.clone(),
        tokens.expires_in,
        tokens.id_token.clone(),
        tokens.scope.clone(),
        tokens.token_type.clone(),
    )
}

fn convert_expires_in(value: Option<i64>) -> Option<u64> {
    value.and_then(|v| if v < 0 { None } else { Some(v as u64) })
}
