use crate::db;

const THEME_FOLLOW_SYSTEM_KEY: &str = "theme_follow_system";
const THEME_MANUAL_MODE_KEY: &str = "theme_manual_mode";
const DEFAULT_FOLLOW_SYSTEM: bool = true;
const DEFAULT_MANUAL_MODE: &str = "light";

pub fn get_theme_follow_system() -> Result<bool, String> {
    if let Some(value) = db::get_setting(THEME_FOLLOW_SYSTEM_KEY)? {
        return parse_bool(&value);
    }
    Ok(DEFAULT_FOLLOW_SYSTEM)
}

pub fn set_theme_follow_system(value: bool) -> Result<bool, String> {
    db::set_setting(THEME_FOLLOW_SYSTEM_KEY, &value.to_string())?;
    Ok(value)
}

pub fn get_theme_manual_mode() -> Result<String, String> {
    if let Some(value) = db::get_setting(THEME_MANUAL_MODE_KEY)? {
        return normalize_theme_mode(&value);
    }
    Ok(DEFAULT_MANUAL_MODE.to_string())
}

pub fn set_theme_manual_mode(mode: String) -> Result<String, String> {
    let normalized = normalize_theme_mode(&mode)?;
    db::set_setting(THEME_MANUAL_MODE_KEY, &normalized)?;
    Ok(normalized)
}

pub fn default_theme_follow_system() -> bool {
    DEFAULT_FOLLOW_SYSTEM
}

pub fn default_theme_manual_mode() -> String {
    DEFAULT_MANUAL_MODE.to_string()
}

fn parse_bool(raw: &str) -> Result<bool, String> {
    raw.trim()
        .parse::<bool>()
        .map_err(|e| format!("invalid theme follow_system value: {e}"))
}

fn normalize_theme_mode(raw: &str) -> Result<String, String> {
    match raw.trim().to_ascii_lowercase().as_str() {
        "light" => Ok("light".to_string()),
        "dark" => Ok("dark".to_string()),
        other => Err(format!("invalid theme mode: {other}")),
    }
}
