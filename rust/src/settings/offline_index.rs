use crate::db;

const OFFLINE_INDEX_ENABLED_KEY: &str = "offline_index_enabled";
const DEFAULT_OFFLINE_INDEX_ENABLED: bool = false;

pub fn get_offline_index_enabled() -> Result<bool, String> {
    if let Some(value) = db::get_setting(OFFLINE_INDEX_ENABLED_KEY)? {
        return parse_bool(&value);
    }
    Ok(DEFAULT_OFFLINE_INDEX_ENABLED)
}

pub fn set_offline_index_enabled(value: bool) -> Result<bool, String> {
    db::set_setting(OFFLINE_INDEX_ENABLED_KEY, &value.to_string())?;
    Ok(value)
}

pub fn default_offline_index_enabled() -> bool {
    DEFAULT_OFFLINE_INDEX_ENABLED
}

fn parse_bool(raw: &str) -> Result<bool, String> {
    raw.trim()
        .parse::<bool>()
        .map_err(|e| format!("invalid offline index enabled value: {e}"))
}
