use crate::db;
use directories::UserDirs;

const DOWNLOAD_DIR_KEY: &str = "download_directory";

pub fn get_download_directory() -> Result<String, String> {
    if let Some(value) = db::get_setting(DOWNLOAD_DIR_KEY)? {
        return Ok(value);
    }
    default_download_directory()
}

pub fn set_download_directory(path: String) -> Result<String, String> {
    if path.trim().is_empty() {
        return Err("download directory cannot be empty".to_string());
    }
    db::set_setting(DOWNLOAD_DIR_KEY, &path)?;
    Ok(path)
}

pub fn default_download_directory() -> Result<String, String> {
    if let Some(user_dirs) = UserDirs::new() {
        let base = user_dirs.download_dir().unwrap_or(user_dirs.home_dir());
        return Ok(base.join("skydrivex").to_string_lossy().into_owned());
    }
    Err("failed to resolve default download directory".to_string())
}
