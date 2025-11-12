mod client;
pub mod download;
pub mod list;
pub mod models;

pub use download::download_drive_item;
pub use list::list_drive_children;
pub use models::{DriveDownloadResult, DriveItemSummary, DrivePage};

/// Graph v1 端点常量，集中声明方便今后切换区域或版本。
pub(crate) const GRAPH_BASE: &str = "https://graph.microsoft.com/v1.0";
