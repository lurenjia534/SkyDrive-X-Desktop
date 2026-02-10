use crate::db;

/// 是否启用离线索引（前端开关）。
const OFFLINE_INDEX_ENABLED_KEY: &str = "offline_index_enabled";
/// 离线索引 delta token（Graph 返回的 `@odata.deltaLink`）。
const OFFLINE_INDEX_DELTA_LINK_KEY: &str = "offline_index_delta_link";
/// 最近一次离线索引同步完成时间（毫秒时间戳）。
const OFFLINE_INDEX_LAST_SYNC_MILLIS_KEY: &str = "offline_index_last_sync_millis";
/// 默认不开启离线索引，避免首次启动额外开销。
const DEFAULT_OFFLINE_INDEX_ENABLED: bool = false;

/// 读取离线索引开关。
pub fn get_offline_index_enabled() -> Result<bool, String> {
    if let Some(value) = db::get_setting(OFFLINE_INDEX_ENABLED_KEY)? {
        return parse_bool(&value);
    }
    Ok(DEFAULT_OFFLINE_INDEX_ENABLED)
}

/// 写入离线索引开关。
pub fn set_offline_index_enabled(value: bool) -> Result<bool, String> {
    db::set_setting(OFFLINE_INDEX_ENABLED_KEY, &value.to_string())?;
    Ok(value)
}

/// 返回离线索引开关默认值。
pub fn default_offline_index_enabled() -> bool {
    DEFAULT_OFFLINE_INDEX_ENABLED
}

/// 读取 delta_link。空串会被视为“无 token”。
pub fn get_offline_index_delta_link() -> Result<Option<String>, String> {
    match db::get_setting(OFFLINE_INDEX_DELTA_LINK_KEY)? {
        Some(value) if !value.trim().is_empty() => Ok(Some(value)),
        _ => Ok(None),
    }
}

/// 写入 delta_link（不能为空）。
pub fn set_offline_index_delta_link(value: String) -> Result<String, String> {
    if value.trim().is_empty() {
        return Err("offline index delta link cannot be empty".to_string());
    }
    db::set_setting(OFFLINE_INDEX_DELTA_LINK_KEY, &value)?;
    Ok(value)
}

/// 清空 delta_link，下一次同步将回到全量路径。
pub fn clear_offline_index_delta_link() -> Result<(), String> {
    db::set_setting(OFFLINE_INDEX_DELTA_LINK_KEY, "")?;
    Ok(())
}

/// 读取最近同步时间（毫秒）。
pub fn get_offline_index_last_sync_millis() -> Result<Option<i64>, String> {
    match db::get_setting(OFFLINE_INDEX_LAST_SYNC_MILLIS_KEY)? {
        Some(raw) if !raw.trim().is_empty() => raw
            .trim()
            .parse::<i64>()
            .map(Some)
            .map_err(|e| format!("invalid offline index last sync millis value: {e}")),
        _ => Ok(None),
    }
}

/// 写入最近同步时间（必须为正数）。
pub fn set_offline_index_last_sync_millis(value: i64) -> Result<i64, String> {
    if value <= 0 {
        return Err("offline index last sync millis must be positive".to_string());
    }
    db::set_setting(OFFLINE_INDEX_LAST_SYNC_MILLIS_KEY, &value.to_string())?;
    Ok(value)
}

/// 解析布尔值配置。
fn parse_bool(raw: &str) -> Result<bool, String> {
    raw.trim()
        .parse::<bool>()
        .map_err(|e| format!("invalid offline index enabled value: {e}"))
}
