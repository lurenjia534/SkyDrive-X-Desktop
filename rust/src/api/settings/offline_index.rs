use crate::settings::offline_index::{
    get_offline_index_enabled as core_get_offline_index_enabled,
    set_offline_index_enabled as core_set_offline_index_enabled,
};

#[flutter_rust_bridge::frb]
pub fn get_offline_index_enabled() -> Result<bool, String> {
    core_get_offline_index_enabled()
}

#[flutter_rust_bridge::frb]
pub fn set_offline_index_enabled(value: bool) -> Result<bool, String> {
    core_set_offline_index_enabled(value)
}
