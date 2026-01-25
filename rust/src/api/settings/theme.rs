use crate::settings::theme::{
    get_theme_follow_system as core_get_theme_follow_system,
    get_theme_manual_mode as core_get_theme_manual_mode,
    set_theme_follow_system as core_set_theme_follow_system,
    set_theme_manual_mode as core_set_theme_manual_mode,
};

/// FRB 对外接口：获取是否跟随系统主题。
#[flutter_rust_bridge::frb]
pub fn get_theme_follow_system() -> Result<bool, String> {
    core_get_theme_follow_system()
}

/// FRB 对外接口：设置是否跟随系统主题。
#[flutter_rust_bridge::frb]
pub fn set_theme_follow_system(value: bool) -> Result<bool, String> {
    core_set_theme_follow_system(value)
}

/// FRB 对外接口：获取手动主题模式（light/dark）。
#[flutter_rust_bridge::frb]
pub fn get_theme_manual_mode() -> Result<String, String> {
    core_get_theme_manual_mode()
}

/// FRB 对外接口：设置手动主题模式（light/dark）。
#[flutter_rust_bridge::frb]
pub fn set_theme_manual_mode(mode: String) -> Result<String, String> {
    core_set_theme_manual_mode(mode)
}
