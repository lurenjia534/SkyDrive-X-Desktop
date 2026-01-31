use super::auth::{
    load_active_auth_record, persist_tokens_for_account, AuthTokens, StoredAuthState,
    TokenResponse, AUTHORITY, TOKEN_PATH,
};
use reqwest::blocking::Client;
use std::time::Duration;

#[flutter_rust_bridge::frb]
pub fn refresh_tokens() -> Result<StoredAuthState, String> {
    let record = load_active_auth_record()?;
    let refresh_token = record.refresh_token.clone().ok_or_else(|| {
        "no refresh token available; interactive authentication required".to_string()
    })?;

    let tokens = exchange_refresh_token(&record.client_id, &refresh_token, record.scope.clone())?;

    let account_id = record.account_id;
    let client_id = record.client_id;
    let display_name = record.display_name;
    let user_principal_name = record.user_principal_name;
    persist_tokens_for_account(
        &account_id,
        &client_id,
        &tokens,
        display_name,
        user_principal_name,
    )
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
