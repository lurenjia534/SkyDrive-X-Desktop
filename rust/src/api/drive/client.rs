use crate::db;
use reqwest::{blocking::Client, redirect::Policy};
use std::time::Duration;

pub(crate) fn current_access_token() -> Result<String, String> {
    let record = db::load_auth_record()?
        .ok_or_else(|| "no authentication state available; please sign in".to_string())?;
    Ok(record.access_token)
}

pub(crate) fn build_blocking_client(timeout: Duration) -> Result<Client, String> {
    Client::builder()
        .timeout(timeout)
        .redirect(Policy::limited(10))
        .build()
        .map_err(|e| format!("failed to build HTTP client: {e}"))
}
