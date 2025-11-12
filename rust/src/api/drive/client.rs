use crate::db;
use reqwest::{blocking::Client, redirect::Policy};
use std::time::Duration;

/// 负责提供 Graph API 所需的 access token。
/// 该函数只做简单封装，调用方不需要直接操作数据库。
pub(crate) fn current_access_token() -> Result<String, String> {
    let record = db::load_auth_record()?
        .ok_or_else(|| "no authentication state available; please sign in".to_string())?;
    Ok(record.access_token)
}

/// 构建一个带有统一超时与重定向策略的阻塞式 HTTP 客户端。
/// 所有 Graph API 调用应尽量复用该函数，避免重复配置。
pub(crate) fn build_blocking_client(timeout: Duration) -> Result<Client, String> {
    Client::builder()
        .timeout(timeout)
        .redirect(Policy::limited(10))
        .build()
        .map_err(|e| format!("failed to build HTTP client: {e}"))
}
