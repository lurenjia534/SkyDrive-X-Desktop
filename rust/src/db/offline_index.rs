use rusqlite::{params, Row};

use super::{with_connection, StorageResult};

pub(crate) const OFFLINE_INDEX_TABLE_SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS offline_index_items (
    item_id TEXT PRIMARY KEY,
    parent_id TEXT,
    name TEXT NOT NULL,
    name_folded TEXT NOT NULL,
    is_folder INTEGER NOT NULL,
    size INTEGER,
    child_count INTEGER,
    mime_type TEXT,
    last_modified TEXT,
    thumbnail_url TEXT,
    indexed_at_millis INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_offline_index_parent_id ON offline_index_items(parent_id);
CREATE INDEX IF NOT EXISTS idx_offline_index_name_folded ON offline_index_items(name_folded);
";

#[derive(Debug, Clone)]
pub struct OfflineIndexRecord {
    pub item_id: String,
    pub parent_id: Option<String>,
    pub name: String,
    pub name_folded: String,
    pub is_folder: bool,
    pub size: Option<i64>,
    pub child_count: Option<i64>,
    pub mime_type: Option<String>,
    pub last_modified: Option<String>,
    pub thumbnail_url: Option<String>,
    pub indexed_at_millis: i64,
}

pub fn replace_offline_index(records: &[OfflineIndexRecord]) -> StorageResult<()> {
    with_connection(|conn| {
        let tx = conn
            .unchecked_transaction()
            .map_err(|e| format!("failed to start offline index transaction: {e}"))?;
        tx.execute("DELETE FROM offline_index_items", [])
            .map_err(|e| format!("failed to clear offline index table: {e}"))?;

        let mut stmt = tx
            .prepare(
                "INSERT INTO offline_index_items (
                    item_id,
                    parent_id,
                    name,
                    name_folded,
                    is_folder,
                    size,
                    child_count,
                    mime_type,
                    last_modified,
                    thumbnail_url,
                    indexed_at_millis
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            )
            .map_err(|e| format!("failed to prepare offline index insert: {e}"))?;

        for record in records {
            stmt.execute(params![
                record.item_id,
                record.parent_id,
                record.name,
                record.name_folded,
                record.is_folder as i64,
                record.size,
                record.child_count,
                record.mime_type,
                record.last_modified,
                record.thumbnail_url,
                record.indexed_at_millis,
            ])
            .map_err(|e| format!("failed to insert offline index item: {e}"))?;
        }

        drop(stmt);
        tx.commit()
            .map_err(|e| format!("failed to commit offline index transaction: {e}"))?;
        Ok(())
    })
}

pub fn count_offline_index_items() -> StorageResult<usize> {
    with_connection(|conn| {
        let count = conn
            .query_row("SELECT COUNT(1) FROM offline_index_items", [], |row| {
                row.get::<_, i64>(0)
            })
            .map_err(|e| format!("failed to count offline index items: {e}"))?;
        Ok((count.max(0)) as usize)
    })
}

pub fn latest_offline_indexed_at_millis() -> StorageResult<Option<i64>> {
    with_connection(|conn| {
        let value = conn
            .query_row(
                "SELECT MAX(indexed_at_millis) FROM offline_index_items",
                [],
                |row| row.get::<_, Option<i64>>(0),
            )
            .map_err(|e| format!("failed to query latest offline indexed timestamp: {e}"))?;
        Ok(value)
    })
}

pub fn search_offline_index_items(
    query: &str,
    folder_id: Option<&str>,
    limit: usize,
    offset: usize,
) -> StorageResult<Vec<OfflineIndexRecord>> {
    let escaped = escape_like_pattern(query);
    let like_pattern = format!("%{escaped}%");
    let limit = limit as i64;
    let offset = offset as i64;
    with_connection(|conn| {
        if let Some(scope_folder_id) = folder_id.filter(|v| !v.trim().is_empty()) {
            let mut stmt = conn
                .prepare(
                    "WITH RECURSIVE scope(item_id) AS (
                        SELECT item_id FROM offline_index_items WHERE parent_id = ?1
                        UNION ALL
                        SELECT child.item_id
                        FROM offline_index_items child
                        INNER JOIN scope parent_scope ON child.parent_id = parent_scope.item_id
                    )
                    SELECT
                        item_id,
                        parent_id,
                        name,
                        name_folded,
                        is_folder,
                        size,
                        child_count,
                        mime_type,
                        last_modified,
                        thumbnail_url,
                        indexed_at_millis
                    FROM offline_index_items
                    WHERE item_id IN scope
                      AND name_folded LIKE ?2 ESCAPE '\\'
                    ORDER BY is_folder DESC, name_folded ASC, item_id ASC
                    LIMIT ?3 OFFSET ?4",
                )
                .map_err(|e| format!("failed to prepare scoped offline search query: {e}"))?;
            let rows = stmt
                .query_map(
                    params![scope_folder_id, like_pattern, limit, offset],
                    map_offline_index_row,
                )
                .map_err(|e| format!("failed to query scoped offline index items: {e}"))?
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| format!("failed to parse scoped offline index row: {e}"))?;
            Ok(rows)
        } else {
            let mut stmt = conn
                .prepare(
                    "SELECT
                        item_id,
                        parent_id,
                        name,
                        name_folded,
                        is_folder,
                        size,
                        child_count,
                        mime_type,
                        last_modified,
                        thumbnail_url,
                        indexed_at_millis
                    FROM offline_index_items
                    WHERE name_folded LIKE ?1 ESCAPE '\\'
                    ORDER BY is_folder DESC, name_folded ASC, item_id ASC
                    LIMIT ?2 OFFSET ?3",
                )
                .map_err(|e| format!("failed to prepare offline search query: {e}"))?;
            let rows = stmt
                .query_map(params![like_pattern, limit, offset], map_offline_index_row)
                .map_err(|e| format!("failed to query offline index items: {e}"))?
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| format!("failed to parse offline index row: {e}"))?;
            Ok(rows)
        }
    })
}

fn map_offline_index_row(row: &Row) -> rusqlite::Result<OfflineIndexRecord> {
    Ok(OfflineIndexRecord {
        item_id: row.get(0)?,
        parent_id: row.get(1)?,
        name: row.get(2)?,
        name_folded: row.get(3)?,
        is_folder: row.get::<_, i64>(4)? != 0,
        size: row.get(5)?,
        child_count: row.get(6)?,
        mime_type: row.get(7)?,
        last_modified: row.get(8)?,
        thumbnail_url: row.get(9)?,
        indexed_at_millis: row.get(10)?,
    })
}

fn escape_like_pattern(raw: &str) -> String {
    let mut escaped = String::with_capacity(raw.len());
    for ch in raw.chars() {
        match ch {
            '%' => escaped.push_str("\\%"),
            '_' => escaped.push_str("\\_"),
            '\\' => escaped.push_str("\\\\"),
            _ => escaped.push(ch),
        }
    }
    escaped
}
