/// 应用设置域：
/// - 下载并发
/// - 下载目录
/// - 离线索引
/// - 主题
pub mod download_concurrency;
pub mod download_directory;
pub mod offline_index;
pub mod theme;

pub use download_concurrency::{
    default_download_concurrency, get_download_concurrency, set_download_concurrency,
    MAX_DOWNLOAD_CONCURRENCY, MIN_DOWNLOAD_CONCURRENCY,
};
pub use download_directory::{
    default_download_directory, get_download_directory, set_download_directory,
};
pub use offline_index::{
    clear_offline_index_delta_link, default_offline_index_enabled, get_offline_index_delta_link,
    get_offline_index_enabled, get_offline_index_last_sync_millis, set_offline_index_delta_link,
    set_offline_index_enabled, set_offline_index_last_sync_millis,
};
pub use theme::{
    default_theme_follow_system, default_theme_manual_mode, get_theme_follow_system,
    get_theme_manual_mode, set_theme_follow_system, set_theme_manual_mode,
};
