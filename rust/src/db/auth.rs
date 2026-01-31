use rusqlite::{params, Connection, OptionalExtension};
use std::convert::TryInto;

use super::{current_timestamp_millis, with_connection, StorageResult};

/// OAuth 令牌持久化模块：支持多账户存储与旧表迁移读取。
/// 由于桌面端可能需要跨多次启动复用 token，所以统一走 sqlite。

pub(crate) const AUTH_ACCOUNTS_TABLE_SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS auth_accounts (
    account_id TEXT PRIMARY KEY,
    client_id TEXT NOT NULL,
    access_token TEXT NOT NULL,
    refresh_token TEXT,
    expires_in_seconds INTEGER,
    id_token TEXT,
    scope TEXT,
    token_type TEXT,
    updated_at_millis INTEGER NOT NULL,
    display_name TEXT,
    user_principal_name TEXT
);";

const LEGACY_AUTH_TABLE_NAME: &str = "auth_tokens";

#[derive(Debug, Clone)]
pub struct AuthAccountRecord {
    pub account_id: String,
    pub client_id: String,
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_in_seconds: Option<i64>,
    pub id_token: Option<String>,
    pub scope: Option<String>,
    pub token_type: Option<String>,
    pub updated_at_millis: i64,
    pub display_name: Option<String>,
    pub user_principal_name: Option<String>,
}

#[derive(Debug, Clone)]
pub struct LegacyAuthTokenRecord {
    pub client_id: String,
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_in_seconds: Option<i64>,
    pub id_token: Option<String>,
    pub scope: Option<String>,
    pub token_type: Option<String>,
    pub updated_at_millis: i64,
}

pub fn upsert_auth_account(record: &AuthAccountRecord) -> StorageResult<()> {
    with_connection(|conn| {
        conn.execute(
            "INSERT INTO auth_accounts (
                account_id,
                client_id,
                access_token,
                refresh_token,
                expires_in_seconds,
                id_token,
                scope,
                token_type,
                updated_at_millis,
                display_name,
                user_principal_name
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_id) DO UPDATE SET
                client_id = excluded.client_id,
                access_token = excluded.access_token,
                refresh_token = excluded.refresh_token,
                expires_in_seconds = excluded.expires_in_seconds,
                id_token = excluded.id_token,
                scope = excluded.scope,
                token_type = excluded.token_type,
                updated_at_millis = excluded.updated_at_millis,
                display_name = excluded.display_name,
                user_principal_name = excluded.user_principal_name",
            params![
                record.account_id,
                record.client_id,
                record.access_token,
                record.refresh_token,
                record.expires_in_seconds,
                record.id_token,
                record.scope,
                record.token_type,
                record.updated_at_millis,
                record.display_name,
                record.user_principal_name,
            ],
        )
        .map_err(|e| format!("failed to upsert auth account: {e}"))?;
        Ok(())
    })
}

pub fn load_auth_account(account_id: &str) -> StorageResult<Option<AuthAccountRecord>> {
    with_connection(|conn| {
        conn.query_row(
            "SELECT
                account_id,
                client_id,
                access_token,
                refresh_token,
                expires_in_seconds,
                id_token,
                scope,
                token_type,
                updated_at_millis,
                display_name,
                user_principal_name
            FROM auth_accounts
            WHERE account_id = ?",
            [account_id],
            |row| {
                Ok(AuthAccountRecord {
                    account_id: row.get(0)?,
                    client_id: row.get(1)?,
                    access_token: row.get(2)?,
                    refresh_token: row.get(3)?,
                    expires_in_seconds: row.get(4)?,
                    id_token: row.get(5)?,
                    scope: row.get(6)?,
                    token_type: row.get(7)?,
                    updated_at_millis: row.get(8)?,
                    display_name: row.get(9)?,
                    user_principal_name: row.get(10)?,
                })
            },
        )
        .optional()
        .map_err(|e| format!("failed to read auth account: {e}"))
    })
}

pub fn list_auth_accounts() -> StorageResult<Vec<AuthAccountRecord>> {
    with_connection(|conn| {
        let mut stmt = conn
            .prepare(
                "SELECT
                    account_id,
                    client_id,
                    access_token,
                    refresh_token,
                    expires_in_seconds,
                    id_token,
                    scope,
                    token_type,
                    updated_at_millis,
                    display_name,
                    user_principal_name
                FROM auth_accounts
                ORDER BY updated_at_millis DESC",
            )
            .map_err(|e| format!("failed to prepare auth accounts query: {e}"))?;
        let rows = stmt
            .query_map([], |row| {
                Ok(AuthAccountRecord {
                    account_id: row.get(0)?,
                    client_id: row.get(1)?,
                    access_token: row.get(2)?,
                    refresh_token: row.get(3)?,
                    expires_in_seconds: row.get(4)?,
                    id_token: row.get(5)?,
                    scope: row.get(6)?,
                    token_type: row.get(7)?,
                    updated_at_millis: row.get(8)?,
                    display_name: row.get(9)?,
                    user_principal_name: row.get(10)?,
                })
            })
            .map_err(|e| format!("failed to query auth accounts: {e}"))?;
        let mut results = Vec::new();
        for row in rows {
            results.push(row.map_err(|e| format!("failed to parse auth account: {e}"))?);
        }
        Ok(results)
    })
}

pub fn delete_auth_account(account_id: &str) -> StorageResult<()> {
    with_connection(|conn| {
        conn.execute(
            "DELETE FROM auth_accounts WHERE account_id = ?",
            [account_id],
        )
        .map_err(|e| format!("failed to delete auth account: {e}"))?;
        Ok(())
    })
}

pub fn clear_auth_accounts() -> StorageResult<()> {
    with_connection(|conn| {
        conn.execute("DELETE FROM auth_accounts", [])
            .map_err(|e| format!("failed to clear auth accounts: {e}"))?;
        Ok(())
    })
}

pub fn load_legacy_auth_record() -> StorageResult<Option<LegacyAuthTokenRecord>> {
    with_connection(|conn| {
        if !legacy_table_exists(conn)? {
            return Ok(None);
        }
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
                Ok(LegacyAuthTokenRecord {
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
        .map_err(|e| format!("failed to read legacy auth tokens: {e}"))
    })
}

pub fn clear_legacy_auth_record() -> StorageResult<()> {
    with_connection(|conn| {
        if !legacy_table_exists(conn)? {
            return Ok(());
        }
        conn.execute("DELETE FROM auth_tokens WHERE id = 1", [])
            .map_err(|e| format!("failed to clear legacy auth tokens: {e}"))?;
        Ok(())
    })
}

pub fn build_account_record(
    account_id: String,
    client_id: String,
    access_token: String,
    refresh_token: Option<String>,
    expires_in_seconds: Option<u64>,
    id_token: Option<String>,
    scope: Option<String>,
    token_type: Option<String>,
    display_name: Option<String>,
    user_principal_name: Option<String>,
) -> AuthAccountRecord {
    AuthAccountRecord {
        account_id,
        client_id,
        access_token,
        refresh_token,
        expires_in_seconds: expires_in_seconds.and_then(|value| value.try_into().ok()),
        id_token,
        scope,
        token_type,
        updated_at_millis: current_timestamp_millis(),
        display_name,
        user_principal_name,
    }
}

fn legacy_table_exists(conn: &Connection) -> StorageResult<bool> {
    let existing: Option<String> = conn
        .query_row(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
            [LEGACY_AUTH_TABLE_NAME],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| format!("failed to query legacy auth table: {e}"))?;
    Ok(existing.is_some())
}
