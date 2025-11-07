use directories::ProjectDirs;
use rusqlite::{params, Connection, OptionalExtension};
use std::convert::TryInto;
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

const QUALIFIER: &str = "com";
const ORGANIZATION: &str = "Skydrivex";
const APPLICATION: &str = "Skydrivex";
const DB_FILE_NAME: &str = "auth.db";

pub type StorageResult<T> = Result<T, String>;

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

pub fn init_storage() -> StorageResult<()> {
    with_connection(|_| Ok(()))
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

fn with_connection<T, F>(operation: F) -> StorageResult<T>
where
    F: FnOnce(&Connection) -> StorageResult<T>,
{
    let conn = open_connection()?;
    operation(&conn)
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
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS auth_tokens (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            client_id TEXT NOT NULL,
            access_token TEXT NOT NULL,
            refresh_token TEXT,
            expires_in_seconds INTEGER,
            id_token TEXT,
            scope TEXT,
            token_type TEXT,
            updated_at_millis INTEGER NOT NULL
        );",
    )
    .map_err(|e| format!("failed to initialize database schema: {e}"))?;
    Ok(())
}

fn database_path() -> StorageResult<PathBuf> {
    let dirs = ProjectDirs::from(QUALIFIER, ORGANIZATION, APPLICATION)
        .ok_or_else(|| "failed to resolve application data directory".to_string())?;
    Ok(dirs.data_dir().join(DB_FILE_NAME))
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

fn current_timestamp_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}
