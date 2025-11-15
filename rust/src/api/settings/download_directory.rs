use crate::settings::download_directory::{
    get_download_directory as core_get_download_directory,
    set_download_directory as core_set_download_directory,
};

#[flutter_rust_bridge::frb]
pub fn get_download_directory() -> Result<String, String> {
    core_get_download_directory()
}

#[flutter_rust_bridge::frb]
pub fn set_download_directory(path: String) -> Result<String, String> {
    core_set_download_directory(path)
}
