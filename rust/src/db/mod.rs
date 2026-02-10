mod auth;
mod download_tasks;
mod offline_index;
mod settings;
mod upload_tasks;

use directories::ProjectDirs;
use rusqlite::{Connection, Error as SqliteError};
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

pub use auth::{
    build_account_record, clear_auth_accounts, clear_legacy_auth_record, delete_auth_account,
    list_auth_accounts, load_auth_account, load_legacy_auth_record, update_auth_account_profile,
    upsert_auth_account, AuthAccountRecord, LegacyAuthTokenRecord,
};
pub use download_tasks::{
    clear_finished_download_tasks, delete_download_task, load_download_tasks, upsert_download_task,
    DownloadTaskRecord,
};
pub use offline_index::{
    clear_offline_index_table, count_offline_index_items, delete_offline_index_item,
    get_offline_index_item, has_offline_index_children, latest_offline_indexed_at_millis,
    replace_main_with_staging, replace_offline_index, search_offline_index_items,
    upsert_offline_index_item, OfflineIndexRecord, OfflineIndexTable,
};
pub use settings::{get_setting, set_setting};
pub use upload_tasks::{
    clear_finished_upload_tasks, delete_upload_task, load_upload_tasks, upsert_upload_task,
    UploadTaskRecord,
};

/// DB 模块：
/// 1. 负责 SQLite 连接与 schema 迁移；
/// 2. 对外 re-export 各子域数据访问函数；
/// 3. 所有业务表共享同一数据库文件，降低部署复杂度。

const QUALIFIER: &str = "com";
const ORGANIZATION: &str = "Skydrivex";
const APPLICATION: &str = "Skydrivex";
const DB_FILE_NAME: &str = "skydrivex.db";

pub type StorageResult<T> = Result<T, String>;

/// 初始化存储（确保数据库可打开并完成迁移）。
pub fn init_storage() -> StorageResult<()> {
    with_connection(|_| Ok(()))
}

/// 内部公共 helper，减少重复打开连接/应用迁移的样板代码。
pub(crate) fn with_connection<T, F>(operation: F) -> StorageResult<T>
where
    F: FnOnce(&Connection) -> StorageResult<T>,
{
    let conn = open_connection()?;
    operation(&conn)
}

/// 获取毫秒时间戳，供各表记录更新时间。
pub(crate) fn current_timestamp_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}

fn open_connection() -> StorageResult<Connection> {
    let path = database_path()?;
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)
            .map_err(|e| format!("failed to create database directory {dir:?}: {e}"))?;
    }

    let conn =
        Connection::open(path).map_err(|e| format!("failed to open SQLite database: {e}"))?;
    apply_migrations(&conn)?;
    Ok(conn)
}

/// 应用所有表结构与兼容性迁移。
fn apply_migrations(conn: &Connection) -> StorageResult<()> {
    conn.execute_batch(auth::AUTH_ACCOUNTS_TABLE_SCHEMA)
        .map_err(|e| format!("failed to initialize auth_accounts schema: {e}"))?;
    conn.execute_batch(download_tasks::DOWNLOAD_TABLE_SCHEMA)
        .map_err(|e| format!("failed to initialize download_tasks schema: {e}"))?;
    conn.execute_batch(upload_tasks::UPLOAD_TABLE_SCHEMA)
        .map_err(|e| format!("failed to initialize upload_tasks schema: {e}"))?;
    conn.execute_batch(offline_index::OFFLINE_INDEX_TABLE_SCHEMA)
        .map_err(|e| format!("failed to initialize offline_index schema: {e}"))?;
    conn.execute_batch(settings::SETTINGS_TABLE_SCHEMA)
        .map_err(|e| format!("failed to initialize settings schema: {e}"))?;
    ensure_column(conn, "download_tasks", "bytes_downloaded", "INTEGER")?;
    ensure_column(conn, "download_tasks", "target_dir", "TEXT")?;
    ensure_column(conn, "download_tasks", "file_name", "TEXT")?;
    ensure_column(conn, "download_tasks", "overwrite", "INTEGER")?;
    ensure_column(conn, "download_tasks", "etag", "TEXT")?;
    ensure_column(conn, "download_tasks", "can_resume", "INTEGER DEFAULT 0")?;
    Ok(())
}

/// 兼容旧版本数据库：若列不存在则新增，若已存在则忽略。
fn ensure_column(
    conn: &Connection,
    table: &str,
    column: &str,
    definition: &str,
) -> StorageResult<()> {
    let sql = format!("ALTER TABLE {table} ADD COLUMN {column} {definition}");
    match conn.execute(&sql, []) {
        Ok(_) => Ok(()),
        Err(SqliteError::SqliteFailure(_, Some(message)))
            if message.contains("duplicate column name") =>
        {
            Ok(())
        }
        Err(err) => Err(format!("failed to add column {column} on {table}: {err}")),
    }
}

/// 计算数据库文件路径（跨平台应用数据目录）。
fn database_path() -> StorageResult<PathBuf> {
    let dirs = ProjectDirs::from(QUALIFIER, ORGANIZATION, APPLICATION)
        .ok_or_else(|| "failed to resolve application data directory".to_string())?;
    Ok(dirs.data_dir().join(DB_FILE_NAME))
}
