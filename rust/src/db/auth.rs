use rusqlite::{params, OptionalExtension};
use std::convert::TryInto;

use super::{current_timestamp_millis, with_connection, StorageResult};

/// OAuth 令牌持久化模块：集中管理 auth_tokens 表的建表语句与 CRUD。
/// 由于桌面端可能需要跨多次启动复用 token，所以统一走 sqlite。

pub(crate) const AUTH_TABLE_SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS auth_tokens (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    client_id TEXT NOT NULL,
    access_token TEXT NOT NULL,
    refresh_token TEXT,
    expires_in_seconds INTEGER,
    id_token TEXT,
    scope TEXT,
    token_type TEXT,
    updated_at_millis INTEGER NOT NULL
);";

#[derive(Debug, Clone)]
pub struct AuthTokenRecord {
    pub client_id: String,
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_in_seconds: Option<i64>,
    pub id_token: Option<String>,
    pub scope: Option<String>,
    pub token_type: Option<String>,
    pub updated_at_millis: i64,
}

pub fn upsert_auth_record(record: &AuthTokenRecord) -> StorageResult<()> {
    with_connection(|conn| {
        conn.execute(
            "INSERT INTO auth_tokens (
                id,
                client_id,
                access_token,
                refresh_token,
                expires_in_seconds,
                id_token,
                scope,
                token_type,
                updated_at_millis
            )
            VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                client_id = excluded.client_id,
                access_token = excluded.access_token,
                refresh_token = excluded.refresh_token,
                expires_in_seconds = excluded.expires_in_seconds,
                id_token = excluded.id_token,
                scope = excluded.scope,
                token_type = excluded.token_type,
                updated_at_millis = excluded.updated_at_millis",
            params![
                record.client_id,
                record.access_token,
                record.refresh_token,
                record.expires_in_seconds,
                record.id_token,
                record.scope,
                record.token_type,
                record.updated_at_millis,
            ],
        )
        .map_err(|e| format!("failed to upsert auth tokens: {e}"))?;
        Ok(())
    })
}

pub fn load_auth_record() -> StorageResult<Option<AuthTokenRecord>> {
    with_connection(|conn| {
        conn.query_row(
            "SELECT
                client_id,
                access_token,
                refresh_token,
                expires_in_seconds,
                id_token,
                scope,
                token_type,
                updated_at_millis
            FROM auth_tokens
            WHERE id = 1",
            [],
            |row| {
                Ok(AuthTokenRecord {
                    client_id: row.get(0)?,
                    access_token: row.get(1)?,
                    refresh_token: row.get(2)?,
                    expires_in_seconds: row.get(3)?,
                    id_token: row.get(4)?,
                    scope: row.get(5)?,
                    token_type: row.get(6)?,
                    updated_at_millis: row.get(7)?,
                })
            },
        )
        .optional()
        .map_err(|e| format!("failed to read auth tokens: {e}"))
    })
}

pub fn clear_auth_record() -> StorageResult<()> {
    with_connection(|conn| {
        conn.execute("DELETE FROM auth_tokens WHERE id = 1", [])
            .map_err(|e| format!("failed to clear auth tokens: {e}"))?;
        Ok(())
    })
}

pub fn build_record(
    client_id: String,
    access_token: String,
    refresh_token: Option<String>,
    expires_in_seconds: Option<u64>,
    id_token: Option<String>,
    scope: Option<String>,
    token_type: Option<String>,
) -> AuthTokenRecord {
    AuthTokenRecord {
        client_id,
        access_token,
        refresh_token,
        expires_in_seconds: expires_in_seconds.and_then(|value| value.try_into().ok()),
        id_token,
        scope,
        token_type,
        updated_at_millis: current_timestamp_millis(),
    }
}
