use super::auth::{
    persist_tokens, AuthTokens, StoredAuthState, TokenResponse, AUTHORITY, TOKEN_PATH,
};
use crate::db;
use reqwest::blocking::Client;
use std::time::Duration;

#[flutter_rust_bridge::frb]
pub fn refresh_tokens() -> Result<StoredAuthState, String> {
    let record = db::load_auth_record()?.ok_or_else(|| {
        "no persisted authentication state found; please sign in first".to_string()
    })?;
    let refresh_token = record.refresh_token.clone().ok_or_else(|| {
        "no refresh token available; interactive authentication required".to_string()
    })?;

    let tokens = exchange_refresh_token(&record.client_id, &refresh_token, record.scope.clone())?;

    persist_tokens(&record.client_id, &tokens)
}

fn exchange_refresh_token(
    client_id: &str,
    refresh_token: &str,
    scope: Option<String>,
) -> Result<AuthTokens, String> {
    let mut params = vec![
        ("client_id", client_id.to_string()),
        ("grant_type", "refresh_token".to_string()),
        ("refresh_token", refresh_token.to_string()),
    ];

    let scoped_value = scope.as_ref().and_then(|scope_value| {
        let trimmed = scope_value.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    });

    if let Some(value) = scoped_value.clone() {
        params.push(("scope", value));
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
        .map_err(|e| format!("token refresh failed: {e}"))?;

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
        refresh_token: payload
            .refresh_token
            .or_else(|| Some(refresh_token.to_string())),
        expires_in: payload.expires_in,
        id_token: payload.id_token,
        scope: payload.scope.or(scope),
        token_type: payload.token_type,
    };

    Ok(tokens)
}
