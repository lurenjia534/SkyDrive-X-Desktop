use rusqlite::{params, Row};

use super::{with_connection, StorageResult};

pub(crate) const UPLOAD_TABLE_SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS upload_tasks (
    task_id TEXT PRIMARY KEY,
    file_name TEXT NOT NULL,
    local_path TEXT NOT NULL,
    size INTEGER,
    mime_type TEXT,
    parent_id TEXT,
    remote_id TEXT,
    status INTEGER NOT NULL,
    started_at INTEGER NOT NULL,
    completed_at INTEGER,
    bytes_uploaded INTEGER,
    error_message TEXT,
    session_url TEXT,
    updated_at_millis INTEGER NOT NULL
);";

#[derive(Debug, Clone)]
pub struct UploadTaskRecord {
    pub task_id: String,
    pub file_name: String,
    pub local_path: String,
    pub size: Option<i64>,
    pub mime_type: Option<String>,
    pub parent_id: Option<String>,
    pub remote_id: Option<String>,
    pub status: i64,
    pub started_at: i64,
    pub completed_at: Option<i64>,
    pub bytes_uploaded: Option<i64>,
    pub error_message: Option<String>,
    pub session_url: Option<String>,
    pub updated_at_millis: i64,
}

pub fn upsert_upload_task(record: &UploadTaskRecord) -> StorageResult<()> {
    with_connection(|conn| {
        conn.execute(
            "INSERT INTO upload_tasks (
                task_id,
                file_name,
                local_path,
                size,
                mime_type,
                parent_id,
                remote_id,
                status,
                started_at,
                completed_at,
                bytes_uploaded,
                error_message,
                session_url,
                updated_at_millis
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(task_id) DO UPDATE SET
                file_name = excluded.file_name,
                local_path = excluded.local_path,
                size = excluded.size,
                mime_type = excluded.mime_type,
                parent_id = excluded.parent_id,
                remote_id = excluded.remote_id,
                status = excluded.status,
                started_at = excluded.started_at,
                completed_at = excluded.completed_at,
                bytes_uploaded = excluded.bytes_uploaded,
                error_message = excluded.error_message,
                session_url = excluded.session_url,
                updated_at_millis = excluded.updated_at_millis",
            params![
                record.task_id,
                record.file_name,
                record.local_path,
                record.size,
                record.mime_type,
                record.parent_id,
                record.remote_id,
                record.status,
                record.started_at,
                record.completed_at,
                record.bytes_uploaded,
                record.error_message,
                record.session_url,
                record.updated_at_millis,
            ],
        )
        .map_err(|e| format!("failed to upsert upload task: {e}"))?;
        Ok(())
    })
}

pub fn load_upload_tasks() -> StorageResult<Vec<UploadTaskRecord>> {
    with_connection(|conn| {
        let mut stmt = conn
            .prepare(
                "SELECT
                    task_id,
                    file_name,
                    local_path,
                    size,
                    mime_type,
                    parent_id,
                    remote_id,
                    status,
                    started_at,
                    completed_at,
                    bytes_uploaded,
                    error_message,
                    session_url,
                    updated_at_millis
                FROM upload_tasks
                ORDER BY started_at ASC",
            )
            .map_err(|e| format!("failed to prepare upload task query: {e}"))?;
        let rows = stmt
            .query_map([], |row| map_upload_task(row))
            .map_err(|e| format!("failed to query upload tasks: {e}"))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("failed to parse upload task row: {e}"))?;
        Ok(rows)
    })
}

pub fn delete_upload_task(task_id: &str) -> StorageResult<()> {
    with_connection(|conn| {
        conn.execute(
            "DELETE FROM upload_tasks WHERE task_id = ?",
            params![task_id],
        )
        .map_err(|e| format!("failed to delete upload task {task_id}: {e}"))?;
        Ok(())
    })
}

pub fn clear_finished_upload_tasks(active_status: i64) -> StorageResult<()> {
    with_connection(|conn| {
        conn.execute(
            "DELETE FROM upload_tasks WHERE status != ?",
            params![active_status],
        )
        .map_err(|e| format!("failed to clear upload history: {e}"))?;
        Ok(())
    })
}

fn map_upload_task(row: &Row) -> rusqlite::Result<UploadTaskRecord> {
    Ok(UploadTaskRecord {
        task_id: row.get(0)?,
        file_name: row.get(1)?,
        local_path: row.get(2)?,
        size: row.get(3)?,
        mime_type: row.get(4)?,
        parent_id: row.get(5)?,
        remote_id: row.get(6)?,
        status: row.get(7)?,
        started_at: row.get(8)?,
        completed_at: row.get(9)?,
        bytes_uploaded: row.get(10)?,
        error_message: row.get(11)?,
        session_url: row.get(12)?,
        updated_at_millis: row.get(13)?,
    })
}
