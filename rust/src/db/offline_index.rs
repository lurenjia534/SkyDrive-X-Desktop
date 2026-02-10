use rusqlite::{params, Row};

use super::{with_connection, StorageResult};

/// 离线索引表结构：
/// - `offline_index_items`：正式索引表（搜索读取）
/// - `offline_index_items_staging`：全量重建时的临时表
/// 两表结构保持一致，便于“staging 构建 -> 原子替换”。
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
CREATE TABLE IF NOT EXISTS offline_index_items_staging (
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
CREATE INDEX IF NOT EXISTS idx_offline_index_staging_parent_id ON offline_index_items_staging(parent_id);
CREATE INDEX IF NOT EXISTS idx_offline_index_staging_name_folded ON offline_index_items_staging(name_folded);
";

/// 离线索引目标表标识。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OfflineIndexTable {
    /// 正式表（线上读写）。
    Main,
    /// 临时表（用于全量重建过程）。
    Staging,
}

/// 离线索引存储记录。
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

/// 全量替换主表内容（覆盖写入）。
/// 主要用于“先收集全量记录再一次性落库”的路径。
pub fn replace_offline_index(records: &[OfflineIndexRecord]) -> StorageResult<()> {
    with_connection(|conn| {
        let tx = conn
            .unchecked_transaction()
            .map_err(|e| format!("failed to start offline index transaction: {e}"))?;
        tx.execute("DELETE FROM offline_index_items", [])
            .map_err(|e| {
                format!(
                    "failed to clear {} table: {e}",
                    table_name(OfflineIndexTable::Main)
                )
            })?;

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

/// 清空指定索引表。
pub fn clear_offline_index_table(table: OfflineIndexTable) -> StorageResult<()> {
    let table_name = table_name(table);
    with_connection(|conn| {
        conn.execute(&format!("DELETE FROM {table_name}"), [])
            .map_err(|e| format!("failed to clear {table_name} table: {e}"))?;
        Ok(())
    })
}

/// 按 `item_id` 插入或更新单条索引记录（幂等 upsert）。
pub fn upsert_offline_index_item(
    table: OfflineIndexTable,
    record: &OfflineIndexRecord,
) -> StorageResult<()> {
    let table_name = table_name(table);
    with_connection(|conn| {
        conn.execute(
            &format!(
                "INSERT INTO {table_name} (
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
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(item_id) DO UPDATE SET
                    parent_id = excluded.parent_id,
                    name = excluded.name,
                    name_folded = excluded.name_folded,
                    is_folder = excluded.is_folder,
                    size = excluded.size,
                    child_count = excluded.child_count,
                    mime_type = excluded.mime_type,
                    last_modified = excluded.last_modified,
                    thumbnail_url = excluded.thumbnail_url,
                    indexed_at_millis = excluded.indexed_at_millis"
            ),
            params![
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
            ],
        )
        .map_err(|e| format!("failed to upsert {table_name} item {}: {e}", record.item_id))?;
        Ok(())
    })
}

/// 删除指定 `item_id` 的索引记录。
pub fn delete_offline_index_item(table: OfflineIndexTable, item_id: &str) -> StorageResult<()> {
    let table_name = table_name(table);
    with_connection(|conn| {
        conn.execute(
            &format!("DELETE FROM {table_name} WHERE item_id = ?1"),
            params![item_id],
        )
        .map_err(|e| format!("failed to delete {table_name} item {item_id}: {e}"))?;
        Ok(())
    })
}

/// 查询指定 `item_id` 的索引记录。
pub fn get_offline_index_item(
    table: OfflineIndexTable,
    item_id: &str,
) -> StorageResult<Option<OfflineIndexRecord>> {
    let table_name = table_name(table);
    with_connection(|conn| {
        let mut stmt = conn
            .prepare(&format!(
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
                FROM {table_name}
                WHERE item_id = ?1
                LIMIT 1"
            ))
            .map_err(|e| format!("failed to prepare {table_name} item lookup: {e}"))?;
        let mut rows = stmt
            .query(params![item_id])
            .map_err(|e| format!("failed to query {table_name} item {item_id}: {e}"))?;
        let next = rows
            .next()
            .map_err(|e| format!("failed to iterate {table_name} item {item_id}: {e}"))?;
        if let Some(row) = next {
            map_offline_index_row(row)
                .map(Some)
                .map_err(|e| format!("failed to map {table_name} item {item_id}: {e}"))
        } else {
            Ok(None)
        }
    })
}

/// 判断某目录 id 是否仍有子项（用于安全删除目录节点）。
pub fn has_offline_index_children(table: OfflineIndexTable, item_id: &str) -> StorageResult<bool> {
    let table_name = table_name(table);
    with_connection(|conn| {
        let value = conn
            .query_row(
                &format!("SELECT EXISTS(SELECT 1 FROM {table_name} WHERE parent_id = ?1 LIMIT 1)"),
                params![item_id],
                |row| row.get::<_, i64>(0),
            )
            .map_err(|e| {
                format!("failed to check children for {table_name} item {item_id}: {e}")
            })?;
        Ok(value != 0)
    })
}

/// staging -> main 原子替换流程：
/// 1. 清空 main；
/// 2. 把 staging 全量拷贝进 main；
/// 3. 清空 staging。
pub fn replace_main_with_staging() -> StorageResult<()> {
    with_connection(|conn| {
        let tx = conn
            .unchecked_transaction()
            .map_err(|e| format!("failed to start offline index swap transaction: {e}"))?;
        tx.execute("DELETE FROM offline_index_items", [])
            .map_err(|e| format!("failed to clear offline index main table during swap: {e}"))?;
        tx.execute(
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
            FROM offline_index_items_staging",
            [],
        )
        .map_err(|e| format!("failed to copy offline index staging table to main: {e}"))?;
        tx.execute("DELETE FROM offline_index_items_staging", [])
            .map_err(|e| format!("failed to clear offline index staging table after swap: {e}"))?;
        tx.commit()
            .map_err(|e| format!("failed to commit offline index swap transaction: {e}"))?;
        Ok(())
    })
}

/// 统计主表索引条数。
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

/// 获取主表中最新 `indexed_at_millis`。
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

/// 在主表中按名称做模糊搜索，支持可选目录作用域与分页。
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

/// 将 SQLite 行映射为 `OfflineIndexRecord`。
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

/// 表枚举转真实表名。
fn table_name(table: OfflineIndexTable) -> &'static str {
    match table {
        OfflineIndexTable::Main => "offline_index_items",
        OfflineIndexTable::Staging => "offline_index_items_staging",
    }
}

/// 转义 SQL LIKE 关键字符（`%`、`_`、`\`），避免误匹配。
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
