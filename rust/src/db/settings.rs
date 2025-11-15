use rusqlite::params;

use super::{current_timestamp_millis, with_connection, StorageResult};

pub(crate) const SETTINGS_TABLE_SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at_millis INTEGER NOT NULL
);";

pub fn get_setting(key: &str) -> StorageResult<Option<String>> {
    with_connection(|conn| {
        let mut stmt = conn
            .prepare("SELECT value FROM settings WHERE key = ?")
            .map_err(|e| format!("failed to prepare settings query: {e}"))?;
        let mut rows = stmt
            .query(params![key])
            .map_err(|e| format!("failed to query setting {key}: {e}"))?;
        let next_row = rows
            .next()
            .map_err(|e| format!("failed to iterate setting {key}: {e}"))?;
        if let Some(row) = next_row {
            let value: String = row
                .get(0)
                .map_err(|e| format!("failed to parse setting {key}: {e}"))?;
            Ok(Some(value))
        } else {
            Ok(None)
        }
    })
}

pub fn set_setting(key: &str, value: &str) -> StorageResult<()> {
    let updated_at = current_timestamp_millis();
    with_connection(|conn| {
        conn.execute(
            "INSERT INTO settings (key, value, updated_at_millis) VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at_millis = excluded.updated_at_millis",
            params![key, value, updated_at],
        )
        .map_err(|e| format!("failed to upsert setting {key}: {e}"))?;
        Ok(())
    })
}
