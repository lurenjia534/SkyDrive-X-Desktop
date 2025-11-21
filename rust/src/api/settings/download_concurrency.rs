use crate::download_manager::DownloadManager;
use crate::settings::download_concurrency::{
    get_download_concurrency as core_get_download_concurrency,
    set_download_concurrency as core_set_download_concurrency,
};

/// FRB 对外接口：获取当前并行下载数设置。
#[flutter_rust_bridge::frb]
pub fn get_download_concurrency() -> Result<u32, String> {
    core_get_download_concurrency().map(|value| value as u32)
}

/// FRB 对外接口：更新并行下载数，并立即通知下载管理器生效。
#[flutter_rust_bridge::frb]
pub fn set_download_concurrency(limit: u32) -> Result<u32, String> {
    let updated = core_set_download_concurrency(limit as usize)?;
    DownloadManager::shared().update_concurrency_limit(updated);
    Ok(updated as u32)
}
