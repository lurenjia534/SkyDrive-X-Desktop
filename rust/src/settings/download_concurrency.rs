use crate::db;

const CONCURRENCY_KEY: &str = "download_max_concurrency";
pub const MIN_DOWNLOAD_CONCURRENCY: usize = 1;
pub const MAX_DOWNLOAD_CONCURRENCY: usize = 8;
const DEFAULT_DOWNLOAD_CONCURRENCY: usize = 4;

/// 从设置表读取并行下载数；缺失时返回默认值，错误时透传。
pub fn get_download_concurrency() -> Result<usize, String> {
    if let Some(value) = db::get_setting(CONCURRENCY_KEY)? {
        return parse_and_clamp(&value);
    }
    Ok(DEFAULT_DOWNLOAD_CONCURRENCY)
}

/// 写入并校验并行下载数，限定在 [MIN, MAX] 区间。
pub fn set_download_concurrency(value: usize) -> Result<usize, String> {
    if value < MIN_DOWNLOAD_CONCURRENCY || value > MAX_DOWNLOAD_CONCURRENCY {
        return Err(format!(
            "download concurrency must be between {} and {}",
            MIN_DOWNLOAD_CONCURRENCY, MAX_DOWNLOAD_CONCURRENCY
        ));
    }
    let value_str = value.to_string();
    db::set_setting(CONCURRENCY_KEY, &value_str)?;
    Ok(value)
}

/// 默认的并行下载数。
pub fn default_download_concurrency() -> usize {
    DEFAULT_DOWNLOAD_CONCURRENCY
}

fn parse_and_clamp(raw: &str) -> Result<usize, String> {
    let parsed = raw
        .parse::<usize>()
        .map_err(|e| format!("invalid download concurrency value: {e}"))?;
    let clamped = parsed.clamp(MIN_DOWNLOAD_CONCURRENCY, MAX_DOWNLOAD_CONCURRENCY);
    Ok(clamped)
}
