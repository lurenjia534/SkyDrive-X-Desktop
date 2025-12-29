use rusqlite::{params, Row};

use super::{with_connection, StorageResult};

/// 下载任务持久化模块：负责 download_tasks 表结构与增删改查。
/// 在应用重启后，可借此恢复队列状态，实现断点续传级别的体验。

pub(crate) const DOWNLOAD_TABLE_SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS download_tasks (
    item_id TEXT PRIMARY KEY,
    item_name TEXT NOT NULL,
    size INTEGER,
    is_folder INTEGER NOT NULL,
    child_count INTEGER,
    mime_type TEXT,
    last_modified TEXT,
    thumbnail_url TEXT,
    status INTEGER NOT NULL,
    started_at INTEGER NOT NULL,
    completed_at INTEGER,
    target_dir TEXT NOT NULL,
    file_name TEXT NOT NULL,
    overwrite INTEGER NOT NULL,
    saved_path TEXT,
    size_label INTEGER,
    bytes_downloaded INTEGER,
    etag TEXT,
    can_resume INTEGER NOT NULL DEFAULT 0,
    error_message TEXT,
    updated_at_millis INTEGER NOT NULL
);";

#[derive(Debug, Clone)]
pub struct DownloadTaskRecord {
    pub item_id: String,
    pub item_name: String,
    pub size: Option<i64>,
    pub is_folder: bool,
    pub child_count: Option<i64>,
    pub mime_type: Option<String>,
    pub last_modified: Option<String>,
    pub thumbnail_url: Option<String>,
    pub status: i64,
    pub started_at: i64,
    pub completed_at: Option<i64>,
    pub target_dir: String,
    pub file_name: String,
    pub overwrite: bool,
    pub saved_path: Option<String>,
    pub size_label: Option<i64>,
    pub bytes_downloaded: Option<i64>,
    pub etag: Option<String>,
    pub can_resume: bool,
    pub error_message: Option<String>,
    pub updated_at_millis: i64,
}

pub fn upsert_download_task(record: &DownloadTaskRecord) -> StorageResult<()> {
    with_connection(|conn| {
        conn.execute(
            "INSERT INTO download_tasks (
                item_id,
                item_name,
                size,
                is_folder,
                child_count,
                mime_type,
                last_modified,
                thumbnail_url,
                status,
                started_at,
                completed_at,
                target_dir,
                file_name,
                overwrite,
                saved_path,
                size_label,
                bytes_downloaded,
                etag,
                can_resume,
                error_message,
                updated_at_millis
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(item_id) DO UPDATE SET
                item_name = excluded.item_name,
                size = excluded.size,
                is_folder = excluded.is_folder,
                child_count = excluded.child_count,
                mime_type = excluded.mime_type,
                last_modified = excluded.last_modified,
                thumbnail_url = excluded.thumbnail_url,
                status = excluded.status,
                started_at = excluded.started_at,
                completed_at = excluded.completed_at,
                target_dir = excluded.target_dir,
                file_name = excluded.file_name,
                overwrite = excluded.overwrite,
                saved_path = excluded.saved_path,
                size_label = excluded.size_label,
                bytes_downloaded = excluded.bytes_downloaded,
                etag = excluded.etag,
                can_resume = excluded.can_resume,
                error_message = excluded.error_message,
                updated_at_millis = excluded.updated_at_millis",
            params![
                record.item_id,
                record.item_name,
                record.size,
                record.is_folder as i64,
                record.child_count,
                record.mime_type,
                record.last_modified,
                record.thumbnail_url,
                record.status,
                record.started_at,
                record.completed_at,
                record.target_dir,
                record.file_name,
                record.overwrite as i64,
                record.saved_path,
                record.size_label,
                record.bytes_downloaded,
                record.etag,
                record.can_resume as i64,
                record.error_message,
                record.updated_at_millis,
            ],
        )
        .map_err(|e| format!("failed to upsert download task: {e}"))?;
        Ok(())
    })
}

pub fn load_download_tasks() -> StorageResult<Vec<DownloadTaskRecord>> {
    with_connection(|conn| {
        let mut stmt = conn
            .prepare(
                "SELECT
                    item_id,
                    item_name,
                    size,
                    is_folder,
                    child_count,
                    mime_type,
                    last_modified,
                    thumbnail_url,
                    status,
                    started_at,
                    completed_at,
                    target_dir,
                    file_name,
                    overwrite,
                    saved_path,
                    size_label,
                    bytes_downloaded,
                    etag,
                    can_resume,
                    error_message,
                    updated_at_millis
                FROM download_tasks
                ORDER BY started_at ASC",
            )
            .map_err(|e| format!("failed to prepare download task query: {e}"))?;
        let rows = stmt
            .query_map([], |row| map_download_task(row))
            .map_err(|e| format!("failed to query download tasks: {e}"))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("failed to parse download task row: {e}"))?;
        Ok(rows)
    })
}

pub fn delete_download_task(item_id: &str) -> StorageResult<()> {
    with_connection(|conn| {
        conn.execute(
            "DELETE FROM download_tasks WHERE item_id = ?",
            params![item_id],
        )
        .map_err(|e| format!("failed to delete download task {item_id}: {e}"))?;
        Ok(())
    })
}

pub fn clear_finished_download_tasks(active_status: i64, paused_status: i64) -> StorageResult<()> {
    with_connection(|conn| {
        conn.execute(
            "DELETE FROM download_tasks WHERE status != ? AND status != ?",
            params![active_status, paused_status],
        )
        .map_err(|e| format!("failed to clear download history: {e}"))?;
        Ok(())
    })
}

fn map_download_task(row: &Row) -> rusqlite::Result<DownloadTaskRecord> {
    Ok(DownloadTaskRecord {
        item_id: row.get(0)?,
        item_name: row.get(1)?,
        size: row.get(2)?,
        is_folder: row.get::<_, i64>(3)? != 0,
        child_count: row.get(4)?,
        mime_type: row.get(5)?,
        last_modified: row.get(6)?,
        thumbnail_url: row.get(7)?,
        status: row.get(8)?,
        started_at: row.get(9)?,
        completed_at: row.get(10)?,
        target_dir: row.get::<_, Option<String>>(11)?.unwrap_or_default(),
        file_name: row.get::<_, Option<String>>(12)?.unwrap_or_default(),
        overwrite: row
            .get::<_, Option<i64>>(13)?
            .unwrap_or(0)
            != 0,
        saved_path: row.get(14)?,
        size_label: row.get(15)?,
        bytes_downloaded: row.get(16)?,
        etag: row.get(17)?,
        can_resume: row
            .get::<_, Option<i64>>(18)?
            .unwrap_or(0)
            != 0,
        error_message: row.get(19)?,
        updated_at_millis: row.get(20)?,
    })
}
