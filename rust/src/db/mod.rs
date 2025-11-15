mod auth;
mod download_tasks;
mod settings;

use directories::ProjectDirs;
use rusqlite::{Connection, Error as SqliteError};
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

pub use auth::{
    build_record, clear_auth_record, load_auth_record, upsert_auth_record, AuthTokenRecord,
};
pub use download_tasks::{
    clear_finished_download_tasks, delete_download_task, load_download_tasks, upsert_download_task,
    DownloadTaskRecord,
};
pub use settings::{get_setting, set_setting};

/// DB 模块：提供统一的 sqlite 连接管理，同时 re-export 领域级 API。
/// 目前支持 auth_tokens 与 download_tasks，两者共用同一数据库文件，便于部署。

const QUALIFIER: &str = "com";
const ORGANIZATION: &str = "Skydrivex";
const APPLICATION: &str = "Skydrivex";
const DB_FILE_NAME: &str = "skydrivex.db";

pub type StorageResult<T> = Result<T, String>;

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

fn apply_migrations(conn: &Connection) -> StorageResult<()> {
    conn.execute_batch(auth::AUTH_TABLE_SCHEMA)
        .map_err(|e| format!("failed to initialize auth_tokens schema: {e}"))?;
    conn.execute_batch(download_tasks::DOWNLOAD_TABLE_SCHEMA)
        .map_err(|e| format!("failed to initialize download_tasks schema: {e}"))?;
    conn.execute_batch(settings::SETTINGS_TABLE_SCHEMA)
        .map_err(|e| format!("failed to initialize settings schema: {e}"))?;
    ensure_column(conn, "download_tasks", "bytes_downloaded", "INTEGER")?;
    Ok(())
}

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

fn database_path() -> StorageResult<PathBuf> {
    let dirs = ProjectDirs::from(QUALIFIER, ORGANIZATION, APPLICATION)
        .ok_or_else(|| "failed to resolve application data directory".to_string())?;
    Ok(dirs.data_dir().join(DB_FILE_NAME))
}
