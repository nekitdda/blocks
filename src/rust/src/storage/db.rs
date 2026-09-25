use super::migration::{merge_foreign_tables, stash_foreign_tables};
use crate::api::models::{AppError, TrackArtistDto, UserAccountDto};
use rusqlite::{Connection, OptionalExtension, params};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// All DB failures surface as `AppError::DbError` via the
/// `From<rusqlite::Error>` impl, so callers using `?` into `AppError`
/// keep the correct category (previously a boxed error mapped to ApiError).
type DbResult<T> = Result<T, AppError>;

/// Default TTL for cached images: 7 days in seconds
pub(crate) const DEFAULT_CACHE_TTL_SECS: i64 = 7 * 24 * 60 * 60;

/// File name of the per-account database inside `accounts/<uid>/`.
pub(crate) const ACCOUNT_DB_FILE: &str = "account.db";

/// Settings that belong to an account rather than to the device. They live in
/// the account database; the device database keeps window, tray, hotkey,
/// output-device and volume settings shared by every account.
pub(crate) const ACCOUNT_SETTING_KEYS: &[&str] = &[
    "account_info",
    "playback_state",
    "audio_quality",
    "equalizer",
    "discord_rpc",
    "lyrics_provider_enabled",
];

/// Audio effect presets are stored as `effect_<id>`; they are per account too.
const ACCOUNT_SETTING_PREFIX: &str = "effect_";

const ACTIVE_ACCOUNT_KEY: &str = "active_account";
const PENDING_CLEANUP_KEY: &str = "pending_account_cleanup";
const MAX_PLAY_HISTORY: i64 = 100;

pub struct AppDatabase {
    conn: Connection,
    path: PathBuf,
}

/// An account known to this device, as stored in the device database.
#[derive(Debug, Clone)]
pub struct StoredAccount {
    pub uid: u64,
    /// Empty once the session was revoked; the account stays listed so the
    /// user can sign in again without losing its local data.
    pub token: String,
    pub login: String,
    pub display_name: Option<String>,
    pub full_name: Option<String>,
    pub avatar_url: Option<String>,
    pub has_plus: bool,
    pub added_at: i64,
    pub last_active_at: i64,
}

const ACCOUNT_COLUMNS: &str =
    "uid, token, login, display_name, full_name, avatar_url, has_plus, added_at, last_active_at";

fn account_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<StoredAccount> {
    Ok(StoredAccount {
        uid: row.get::<_, i64>(0)? as u64,
        token: row.get(1)?,
        login: row.get(2)?,
        display_name: row.get(3)?,
        full_name: row.get(4)?,
        avatar_url: row.get(5)?,
        has_plus: row.get::<_, i64>(6)? != 0,
        added_at: row.get(7)?,
        last_active_at: row.get(8)?,
    })
}

/// SQL predicate selecting per-account rows of `app_settings`.
fn account_settings_predicate() -> String {
    let keys = ACCOUNT_SETTING_KEYS
        .iter()
        .map(|k| format!("'{k}'"))
        .collect::<Vec<_>>()
        .join(",");
    format!(
        "(key IN ({keys}) OR substr(key, 1, {}) = '{ACCOUNT_SETTING_PREFIX}')",
        ACCOUNT_SETTING_PREFIX.len()
    )
}

/// Row copy behind `import_legacy_account_data`; `legacy` is attached.
fn copy_legacy_account_rows(conn: &mut Connection) -> DbResult<()> {
    let tx = conn.transaction()?;
    tx.execute(
        "INSERT OR IGNORE INTO main.liked_tracks (track_id)
         SELECT track_id FROM legacy.liked_tracks",
        [],
    )?;
    tx.execute(
        "INSERT OR IGNORE INTO main.track_metadata
         (track_id, title, version, album, album_id, cover_url, duration_ms)
         SELECT track_id, title, version, album, album_id, cover_url, duration_ms
         FROM legacy.track_metadata",
        [],
    )?;
    tx.execute(
        "INSERT OR IGNORE INTO main.track_metadata_artists (track_id, artist_id, name, position)
         SELECT track_id, artist_id, name, position FROM legacy.track_metadata_artists
         WHERE track_id IN (SELECT track_id FROM main.track_metadata)",
        [],
    )?;
    tx.execute(
        &format!(
            "INSERT OR IGNORE INTO main.app_settings (key, value)
             SELECT key, COALESCE(value, '') FROM legacy.app_settings WHERE {}",
            account_settings_predicate()
        ),
        [],
    )?;
    tx.commit()?;
    Ok(())
}

#[derive(Debug, Clone)]
pub struct TrackMetadata {
    pub id: String,
    pub title: String,
    pub version: Option<String>,
    pub artists: Vec<TrackArtistDto>,
    pub album: Option<String>,
    pub album_id: Option<String>,
    pub cover_url: Option<String>,
    pub duration_ms: u64,
}

const CREATE_APP_SETTINGS: &str = "CREATE TABLE IF NOT EXISTS app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL DEFAULT ''
)";

const CREATE_LIKED_TRACKS: &str = "CREATE TABLE IF NOT EXISTS liked_tracks (
    track_id TEXT PRIMARY KEY
)";

const CREATE_CACHE_METADATA: &str = "CREATE TABLE IF NOT EXISTS cache_metadata (
    url TEXT PRIMARY KEY,
    file_path TEXT NOT NULL,
    size INTEGER NOT NULL,
    last_access_at INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL DEFAULT 0,
    etag TEXT
)";

const CREATE_TRACK_METADATA: &str = "CREATE TABLE IF NOT EXISTS track_metadata (
    track_id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    version TEXT,
    album TEXT,
    album_id TEXT,
    cover_url TEXT,
    duration_ms INTEGER NOT NULL
)";

const CREATE_TRACK_ARTISTS: &str = "CREATE TABLE IF NOT EXISTS track_metadata_artists (
    track_id TEXT NOT NULL,
    artist_id TEXT NOT NULL,
    name TEXT NOT NULL,
    position INTEGER NOT NULL,
    PRIMARY KEY (track_id, position),
    FOREIGN KEY (track_id) REFERENCES track_metadata(track_id) ON DELETE CASCADE
)";

const CREATE_ACCOUNTS: &str = "CREATE TABLE IF NOT EXISTS accounts (
    uid INTEGER PRIMARY KEY,
    token TEXT NOT NULL DEFAULT '',
    login TEXT NOT NULL DEFAULT '',
    display_name TEXT,
    full_name TEXT,
    avatar_url TEXT,
    has_plus INTEGER NOT NULL DEFAULT 0,
    added_at INTEGER NOT NULL DEFAULT 0,
    last_active_at INTEGER NOT NULL DEFAULT 0
)";

const CREATE_PLAY_HISTORY: &str = "CREATE TABLE IF NOT EXISTS play_history (
    track_id TEXT PRIMARY KEY,
    played_at INTEGER NOT NULL
)";

const CREATE_INDEXES: &[&str] = &[
    "CREATE INDEX IF NOT EXISTS idx_cache_last_access ON cache_metadata(last_access_at)",
    "CREATE INDEX IF NOT EXISTS idx_cache_expires_at ON cache_metadata(expires_at)",
    "CREATE INDEX IF NOT EXISTS idx_track_artists_id ON track_metadata_artists(track_id)",
    "CREATE INDEX IF NOT EXISTS idx_track_artists_name ON track_metadata_artists(name)",
    "CREATE INDEX IF NOT EXISTS idx_metadata_search_title ON track_metadata(title)",
];

const ACCOUNT_INDEXES: &[&str] = &[
    "CREATE INDEX IF NOT EXISTS idx_track_artists_id ON track_metadata_artists(track_id)",
    "CREATE INDEX IF NOT EXISTS idx_track_artists_name ON track_metadata_artists(name)",
    "CREATE INDEX IF NOT EXISTS idx_metadata_search_title ON track_metadata(title)",
    "CREATE INDEX IF NOT EXISTS idx_play_history_played_at ON play_history(played_at)",
];

impl AppDatabase {
    /// Opens the device database (`yamusic_v2.db`).
    pub async fn init(base_path: Option<PathBuf>) -> DbResult<Self> {
        // Sync SQLite I/O (open + one-time migration) must not stall the executor.
        tokio::task::block_in_place(|| {
            // Same file the toasty backend used, so in-place migration is possible.
            let db_path = if let Some(path) = base_path {
                std::fs::create_dir_all(&path).ok();
                path.join("yamusic_v2.db")
            } else if let Some(proj_dirs) =
                directories::ProjectDirs::from("com", "yamusic", "yamusic")
            {
                let data_dir = proj_dirs.data_dir();
                std::fs::create_dir_all(data_dir).ok();
                data_dir.join("yamusic_v2.db")
            } else {
                PathBuf::from("yamusic_v2.db")
            };

            let conn = Self::open_connection(&db_path)?;

            // Phase 1: move foreign tables aside so CREATE below can't
            // silently reuse a wrong schema under our names.
            stash_foreign_tables(&conn);

            for m in [
                CREATE_APP_SETTINGS,
                CREATE_LIKED_TRACKS,
                CREATE_CACHE_METADATA,
                CREATE_TRACK_METADATA,
                CREATE_TRACK_ARTISTS,
                CREATE_ACCOUNTS,
            ] {
                conn.execute(m, [])?;
            }
            for idx in CREATE_INDEXES {
                conn.execute(idx, [])?;
            }

            // Phase 3: merge the stashed leftovers into the fresh schema.
            merge_foreign_tables(&conn);

            let mut db = Self {
                conn,
                path: db_path,
            };
            db.import_liked_from_settings();
            Ok(db)
        })
    }

    /// Opens (creating on first use) the database of one account in `dir`.
    pub async fn open_account(dir: &Path) -> DbResult<Self> {
        tokio::task::block_in_place(|| {
            std::fs::create_dir_all(dir).map_err(|e| AppError::IoError(e.to_string()))?;
            let db_path = dir.join(ACCOUNT_DB_FILE);
            let conn = Self::open_connection(&db_path)?;
            for m in [
                CREATE_APP_SETTINGS,
                CREATE_LIKED_TRACKS,
                CREATE_TRACK_METADATA,
                CREATE_TRACK_ARTISTS,
                CREATE_PLAY_HISTORY,
            ] {
                conn.execute(m, [])?;
            }
            for idx in ACCOUNT_INDEXES {
                conn.execute(idx, [])?;
            }
            Ok(Self {
                conn,
                path: db_path,
            })
        })
    }

    fn open_connection(path: &Path) -> DbResult<Connection> {
        let conn = Connection::open(path)?;
        // Performance optimizations (same as the pre-toasty backend).
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "synchronous", "NORMAL")?;
        conn.pragma_update(None, "cache_size", -30000)?; // ~30MB cache
        conn.pragma_update(None, "temp_store", "MEMORY")?;
        conn.pragma_update(None, "foreign_keys", "ON")?;
        Ok(conn)
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Releases the database file (checkpointing the WAL) so the account
    /// directory can be deleted. Handles still held by finished tasks keep
    /// working against an empty in-memory database and fail softly.
    pub fn close(&mut self) {
        let Ok(placeholder) = Connection::open_in_memory() else {
            return;
        };
        let conn = std::mem::replace(&mut self.conn, placeholder);
        if let Err((_, e)) = conn.close() {
            tracing::warn!("Failed to close database {:?}: {}", self.path, e);
        }
    }

    /// One-time import: toasty kept liked tracks as a JSON array in settings.
    /// Moves them into the dedicated table, then removes the key.
    fn import_liked_from_settings(&mut self) {
        let raw: Option<String> = self
            .conn
            .query_row(
                "SELECT value FROM app_settings WHERE key = 'liked_tracks'",
                [],
                |r| r.get(0),
            )
            .optional()
            .unwrap_or(None)
            .flatten();
        let Some(raw) = raw else { return };
        let ids: Vec<String> = match serde_json::from_str(&raw) {
            Ok(v) => v,
            Err(e) => {
                tracing::warn!("Failed to parse legacy liked_tracks setting: {}", e);
                return;
            }
        };
        if ids.is_empty() {
            let _ = self
                .conn
                .execute("DELETE FROM app_settings WHERE key = 'liked_tracks'", []);
            return;
        }
        let tx = match self.conn.transaction() {
            Ok(tx) => tx,
            Err(e) => {
                tracing::warn!("Liked tracks import failed: {}", e);
                return;
            }
        };
        let mut ok = true;
        for id in &ids {
            if tx
                .execute(
                    "INSERT OR IGNORE INTO liked_tracks (track_id) VALUES (?1)",
                    params![id],
                )
                .is_err()
            {
                ok = false;
                break;
            }
        }
        if ok {
            ok = tx
                .execute("DELETE FROM app_settings WHERE key = 'liked_tracks'", [])
                .is_ok()
                && tx.commit().is_ok();
        }
        if !ok {
            tracing::warn!("Liked tracks import failed, keeping settings copy");
        }
    }

    pub async fn save_auth_token(&mut self, token: &str, user_id: u64) -> DbResult<()> {
        // Same JSON shape the toasty backend wrote: ["token", uid].
        self.save_setting("auth_token", &(token.to_string(), user_id))
            .await
    }

    pub async fn load_auth_token(&mut self) -> DbResult<Option<(String, u64)>> {
        let raw = self.load_app_setting("auth_token").await?;
        match raw {
            None => Ok(None),
            Some(v) => {
                // Toasty-era format: JSON array.
                if let Ok(parsed) = serde_json::from_str::<(String, u64)>(&v) {
                    return Ok(Some(parsed));
                }
                // Pre-toasty format: "token:uid".
                if let Some((tok, uid)) = v.rsplit_once(':')
                    && let Ok(uid) = uid.parse::<u64>()
                {
                    return Ok(Some((tok.to_string(), uid)));
                }
                tracing::warn!("Unrecognized auth_token format, dropping");
                Ok(None)
            }
        }
    }

    pub async fn delete_auth_token(&mut self) -> DbResult<()> {
        self.conn
            .execute("DELETE FROM app_settings WHERE key = 'auth_token'", [])?;
        Ok(())
    }

    // ---- Account registry (device database) ----

    pub async fn list_accounts(&mut self) -> DbResult<Vec<StoredAccount>> {
        let mut stmt = self.conn.prepare(&format!(
            "SELECT {ACCOUNT_COLUMNS} FROM accounts ORDER BY added_at ASC, uid ASC"
        ))?;
        let accounts = stmt
            .query_map([], account_from_row)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(accounts)
    }

    pub async fn get_account(&mut self, uid: u64) -> DbResult<Option<StoredAccount>> {
        Ok(self
            .conn
            .query_row(
                &format!("SELECT {ACCOUNT_COLUMNS} FROM accounts WHERE uid = ?1"),
                params![uid as i64],
                account_from_row,
            )
            .optional()?)
    }

    /// Adds the account or replaces its token, keeping `added_at` (list order).
    pub async fn save_account_token(&mut self, uid: u64, token: &str) -> DbResult<()> {
        let now = chrono::Utc::now().timestamp_millis();
        self.conn.execute(
            "INSERT INTO accounts (uid, token, added_at) VALUES (?1, ?2, ?3)
             ON CONFLICT(uid) DO UPDATE SET token = excluded.token",
            params![uid as i64, token, now],
        )?;
        Ok(())
    }

    pub async fn save_account_profile(&mut self, profile: &UserAccountDto) -> DbResult<()> {
        self.conn.execute(
            "UPDATE accounts SET login = ?2, display_name = ?3, full_name = ?4,
             avatar_url = ?5, has_plus = ?6 WHERE uid = ?1",
            params![
                profile.uid,
                profile.login,
                profile.display_name,
                profile.full_name,
                profile.avatar_url,
                profile.has_plus as i64
            ],
        )?;
        Ok(())
    }

    pub async fn clear_account_token(&mut self, uid: u64) -> DbResult<()> {
        self.conn.execute(
            "UPDATE accounts SET token = '' WHERE uid = ?1",
            params![uid as i64],
        )?;
        Ok(())
    }

    pub async fn delete_account(&mut self, uid: u64) -> DbResult<()> {
        let tx = self.conn.transaction()?;
        tx.execute("DELETE FROM accounts WHERE uid = ?1", params![uid as i64])?;
        tx.execute(
            "DELETE FROM app_settings WHERE key = ?1 AND value = ?2",
            params![ACTIVE_ACCOUNT_KEY, uid.to_string()],
        )?;
        tx.commit()?;
        Ok(())
    }

    pub async fn mark_account_active(&mut self, uid: u64) -> DbResult<()> {
        let now = chrono::Utc::now().timestamp_millis();
        let tx = self.conn.transaction()?;
        tx.execute(
            "UPDATE accounts SET last_active_at = ?2 WHERE uid = ?1",
            params![uid as i64, now],
        )?;
        tx.execute(
            "INSERT INTO app_settings (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            params![ACTIVE_ACCOUNT_KEY, uid.to_string()],
        )?;
        tx.commit()?;
        Ok(())
    }

    pub async fn load_active_account_uid(&mut self) -> DbResult<Option<u64>> {
        Ok(self
            .load_app_setting(ACTIVE_ACCOUNT_KEY)
            .await?
            .and_then(|v| v.trim().parse::<u64>().ok()))
    }

    /// Account directories whose deletion failed (e.g. a file was locked).
    pub async fn load_pending_account_cleanup(&mut self) -> DbResult<Vec<u64>> {
        Ok(self
            .load_setting::<Vec<u64>>(PENDING_CLEANUP_KEY)
            .await?
            .unwrap_or_default())
    }

    pub async fn save_pending_account_cleanup(&mut self, uids: &[u64]) -> DbResult<()> {
        if uids.is_empty() {
            self.conn.execute(
                "DELETE FROM app_settings WHERE key = ?1",
                params![PENDING_CLEANUP_KEY],
            )?;
            return Ok(());
        }
        self.save_setting(PENDING_CLEANUP_KEY, &uids).await
    }

    /// Copies the library and listening preferences a single-account install
    /// kept in the device database into this account database. Idempotent, so
    /// an interrupted migration simply runs again on the next start.
    pub async fn import_legacy_account_data(&mut self, device_db: &Path) -> DbResult<()> {
        tokio::task::block_in_place(|| {
            self.conn.execute(
                "ATTACH DATABASE ?1 AS legacy",
                params![device_db.to_string_lossy().into_owned()],
            )?;
            let result = copy_legacy_account_rows(&mut self.conn);
            if let Err(e) = self.conn.execute("DETACH DATABASE legacy", []) {
                tracing::warn!("Failed to detach legacy database: {}", e);
            }
            result
        })
    }

    /// Drops per-account rows from the device database once they have been
    /// moved into an account database (or when no account owns them).
    pub async fn purge_legacy_account_data(&mut self) -> DbResult<()> {
        tokio::task::block_in_place(|| {
            let tx = self.conn.transaction()?;
            tx.execute("DELETE FROM liked_tracks", [])?;
            tx.execute("DELETE FROM track_metadata_artists", [])?;
            tx.execute("DELETE FROM track_metadata", [])?;
            tx.execute(
                &format!(
                    "DELETE FROM app_settings WHERE {}",
                    account_settings_predicate()
                ),
                [],
            )?;
            tx.commit()?;
            Ok(())
        })
    }

    // ---- Listening history (account database) ----

    pub async fn record_played_track(&mut self, metadata: TrackMetadata) -> DbResult<()> {
        let track_id = metadata.id.clone();
        self.upsert_track_metadata(metadata).await?;
        let now = chrono::Utc::now().timestamp_millis();
        self.conn.execute(
            "INSERT INTO play_history (track_id, played_at) VALUES (?1, ?2)
             ON CONFLICT(track_id) DO UPDATE SET played_at = excluded.played_at",
            params![track_id, now],
        )?;
        self.conn.execute(
            "DELETE FROM play_history WHERE track_id NOT IN
             (SELECT track_id FROM play_history ORDER BY played_at DESC LIMIT ?1)",
            params![MAX_PLAY_HISTORY],
        )?;
        Ok(())
    }

    pub async fn load_play_history(&mut self, limit: u32) -> DbResult<Vec<TrackMetadata>> {
        let ids: Vec<String> = {
            let mut stmt = self
                .conn
                .prepare("SELECT track_id FROM play_history ORDER BY played_at DESC LIMIT ?1")?;
            stmt.query_map(params![limit as i64], |r| r.get(0))?
                .collect::<rusqlite::Result<_>>()?
        };
        self.get_track_metadata(&ids).await
    }

    pub async fn update_cache_metadata(
        &mut self,
        url: &str,
        file_path: &str,
        size: u64,
        etag: Option<&str>,
    ) -> DbResult<()> {
        let now = chrono::Utc::now().timestamp();
        let expires_at = now + DEFAULT_CACHE_TTL_SECS;
        self.conn.execute(
            "INSERT INTO cache_metadata (url, file_path, size, last_access_at, created_at, expires_at, etag)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT(url) DO UPDATE SET
             file_path = excluded.file_path,
             last_access_at = excluded.last_access_at,
             size = excluded.size,
             etag = excluded.etag,
             expires_at = excluded.expires_at",
            params![url, file_path, size as i64, now, now, expires_at, etag],
        )?;
        Ok(())
    }

    pub async fn get_cache_metadata(
        &mut self,
        url: &str,
    ) -> DbResult<Option<(String, Option<String>, bool)>> {
        let row: Option<(String, Option<String>, i64)> = self
            .conn
            .query_row(
                "SELECT file_path, etag, expires_at FROM cache_metadata WHERE url = ?1",
                params![url],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .optional()?;
        match row {
            None => Ok(None),
            Some((path, etag, expires_at)) => {
                let now = chrono::Utc::now().timestamp();
                let is_expired = now >= expires_at;
                if !is_expired {
                    let new_expires = now + DEFAULT_CACHE_TTL_SECS;
                    let _ = self.conn.execute(
                        "UPDATE cache_metadata SET last_access_at = ?1, expires_at = ?2 WHERE url = ?3",
                        params![now, new_expires, url],
                    );
                }
                Ok(Some((path, etag, is_expired)))
            }
        }
    }

    pub async fn prune_expired(&mut self) -> DbResult<Vec<String>> {
        let now = chrono::Utc::now().timestamp();
        let mut stmt = self
            .conn
            .prepare("SELECT file_path FROM cache_metadata WHERE expires_at <= ?1")?;
        let paths: Vec<String> = stmt
            .query_map(params![now], |r| r.get(0))?
            .collect::<rusqlite::Result<_>>()?;
        if !paths.is_empty() {
            self.conn.execute(
                "DELETE FROM cache_metadata WHERE expires_at <= ?1",
                params![now],
            )?;
        }
        Ok(paths)
    }

    pub async fn prune_cache(&mut self, max_size_bytes: i64) -> DbResult<Vec<String>> {
        // Full-table scan + deletes: keep off the async executor.
        tokio::task::block_in_place(|| {
            let current_size: i64 = self.conn.query_row(
                "SELECT COALESCE(SUM(size), 0) FROM cache_metadata",
                [],
                |r| r.get(0),
            )?;
            if current_size <= max_size_bytes {
                return Ok(vec![]);
            }

            let target_size = (max_size_bytes as f64 * 0.8) as i64;
            let mut to_delete: Vec<(String, String)> = Vec::new();
            let mut deleted_size = 0i64;

            let mut stmt = self.conn.prepare(
                "SELECT url, file_path, size FROM cache_metadata ORDER BY last_access_at ASC",
            )?;
            let mut rows = stmt.query([])?;
            while let Some(row) = rows.next()? {
                if current_size - deleted_size <= target_size {
                    break;
                }
                let url: String = row.get(0)?;
                let path: String = row.get(1)?;
                let size: i64 = row.get(2)?;
                to_delete.push((url, path));
                deleted_size += size;
            }
            drop(rows);

            let mut paths = Vec::with_capacity(to_delete.len());
            for (url, path) in to_delete {
                match self
                    .conn
                    .execute("DELETE FROM cache_metadata WHERE url = ?1", params![url])
                {
                    Ok(1..) => paths.push(path),
                    Ok(0) => tracing::warn!(
                        "prune_cache: row already gone for {}, keeping file list consistent",
                        url
                    ),
                    Err(e) => tracing::warn!("prune_cache: failed to delete {}: {}", url, e),
                }
            }
            Ok(paths)
        })
    }

    pub async fn get_cache_size(&mut self) -> DbResult<i64> {
        Ok(self.conn.query_row(
            "SELECT COALESCE(SUM(size), 0) FROM cache_metadata",
            [],
            |r| r.get(0),
        )?)
    }

    pub async fn clear_cache_metadata(&mut self) -> DbResult<()> {
        self.conn.execute("DELETE FROM cache_metadata", [])?;
        Ok(())
    }

    pub async fn save_playback_state(
        &mut self,
        track_id: &str,
        position_ms: u64,
        is_playing: bool,
    ) -> DbResult<()> {
        self.save_setting(
            "playback_state",
            &(track_id.to_string(), position_ms, is_playing),
        )
        .await
    }

    pub async fn load_playback_state(&mut self) -> DbResult<Option<(String, u64, bool)>> {
        self.load_setting("playback_state").await
    }

    pub async fn save_download_path(&mut self, path: &str) -> DbResult<()> {
        self.save_setting("download_path", &path.to_string()).await
    }

    pub async fn load_download_path(&mut self) -> DbResult<Option<String>> {
        self.load_setting("download_path").await
    }

    pub async fn save_liked_tracks(&mut self, track_ids: &[String]) -> DbResult<()> {
        let tx = self.conn.transaction()?;
        tx.execute("DELETE FROM liked_tracks", [])?;
        {
            let mut stmt =
                tx.prepare("INSERT OR IGNORE INTO liked_tracks (track_id) VALUES (?1)")?;
            for id in track_ids {
                stmt.execute(params![id])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    pub async fn load_liked_tracks(&mut self) -> DbResult<Vec<String>> {
        let mut stmt = self.conn.prepare("SELECT track_id FROM liked_tracks")?;
        let ids: Vec<String> = stmt
            .query_map([], |row| row.get::<_, String>(0))?
            .collect::<rusqlite::Result<_>>()?;
        Ok(ids)
    }

    pub async fn add_liked_track(&mut self, track_id: &str) -> DbResult<()> {
        self.conn.execute(
            "INSERT OR IGNORE INTO liked_tracks (track_id) VALUES (?1)",
            params![track_id],
        )?;
        Ok(())
    }

    pub async fn remove_liked_track(&mut self, track_id: &str) -> DbResult<()> {
        self.conn.execute(
            "DELETE FROM liked_tracks WHERE track_id = ?1",
            params![track_id],
        )?;
        Ok(())
    }

    /// Batched variant of `upsert_track_metadata`: one transaction for the
    /// whole batch.
    ///
    /// The single-row version opened (and committed) a WAL transaction per
    /// track while holding the process-wide `Mutex<AppDatabase>`, so a 5k-track
    /// first sync meant 5k transactions that blocked the playback-progress
    /// writer, the settings worker and every UI read.
    pub async fn upsert_track_metadata_many(
        &mut self,
        items: &[TrackMetadata],
    ) -> DbResult<()> {
        if items.is_empty() {
            return Ok(());
        }
        let tx = self.conn.transaction()?;
        {
            let mut upsert = tx.prepare(
                "INSERT INTO track_metadata (track_id, title, version, album, album_id, cover_url, duration_ms)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                 ON CONFLICT(track_id) DO UPDATE SET
                 title = excluded.title,
                 version = excluded.version,
                 album = excluded.album,
                 album_id = excluded.album_id,
                 cover_url = excluded.cover_url,
                 duration_ms = excluded.duration_ms",
            )?;
            let mut delete_artists =
                tx.prepare("DELETE FROM track_metadata_artists WHERE track_id = ?1")?;
            let mut insert_artist = tx.prepare(
                "INSERT INTO track_metadata_artists (track_id, artist_id, name, position)
                 VALUES (?1, ?2, ?3, ?4)",
            )?;

            for metadata in items {
                upsert.execute(params![
                    metadata.id,
                    metadata.title,
                    metadata.version,
                    metadata.album,
                    metadata.album_id,
                    metadata.cover_url,
                    metadata.duration_ms as i64
                ])?;
                delete_artists.execute(params![metadata.id])?;
                for (i, artist) in metadata.artists.iter().enumerate() {
                    insert_artist.execute(params![
                        metadata.id,
                        artist.id,
                        artist.name,
                        i as i64
                    ])?;
                }
            }
        }
        tx.commit()?;
        Ok(())
    }

    pub async fn upsert_track_metadata(&mut self, metadata: TrackMetadata) -> DbResult<()> {
        self.upsert_track_metadata_many(std::slice::from_ref(&metadata))
            .await
    }

    pub async fn get_track_metadata(
        &mut self,
        track_ids: &[String],
    ) -> DbResult<Vec<TrackMetadata>> {
        // Chunked multi-row reads: keep off the async executor.
        tokio::task::block_in_place(|| {
            if track_ids.is_empty() {
                return Ok(vec![]);
            }

            // Chunked to stay under the SQLite variable limit (999).
            let mut by_id: HashMap<String, TrackMetadata> = HashMap::new();
            for chunk in track_ids.chunks(900) {
                let placeholders = chunk.iter().map(|_| "?").collect::<Vec<_>>().join(",");
                let query = format!(
                    "SELECT track_id, title, version, album, album_id, cover_url, duration_ms
                 FROM track_metadata WHERE track_id IN ({})",
                    placeholders
                );
                let mut stmt = self.conn.prepare(&query)?;
                let rows = stmt.query_map(rusqlite::params_from_iter(chunk), |row| {
                    Ok(TrackMetadata {
                        id: row.get(0)?,
                        title: row.get(1)?,
                        version: row.get(2)?,
                        artists: Vec::new(),
                        album: row.get(3)?,
                        album_id: row.get(4)?,
                        cover_url: row.get(5)?,
                        duration_ms: row.get::<_, i64>(6)? as u64,
                    })
                })?;
                for t in rows {
                    let t = t?;
                    by_id.insert(t.id.clone(), t);
                }

                let artist_query = format!(
                    "SELECT track_id, artist_id, name
                 FROM track_metadata_artists
                 WHERE track_id IN ({})
                 ORDER BY track_id, position ASC",
                    placeholders
                );
                let mut artist_stmt = self.conn.prepare(&artist_query)?;
                let artist_rows =
                    artist_stmt.query_map(rusqlite::params_from_iter(chunk), |row| {
                        Ok((
                            row.get::<_, String>(0)?,
                            TrackArtistDto {
                                id: row.get(1)?,
                                name: row.get(2)?,
                            },
                        ))
                    })?;
                for res in artist_rows {
                    let (tid, artist) = res?;
                    if let Some(track) = by_id.get_mut(&tid) {
                        track.artists.push(artist);
                    }
                }
            }

            // Restore the requested order, skip unknown ids.
            let mut results = Vec::new();
            for id in track_ids {
                if let Some(t) = by_id.remove(id) {
                    results.push(t);
                }
            }
            Ok(results)
        })
    }

    pub async fn save_equalizer(&mut self, enabled: bool, bands: &[f32]) -> DbResult<()> {
        self.save_setting("equalizer", &(enabled, bands)).await
    }

    pub async fn load_equalizer(&mut self) -> DbResult<Option<(bool, Vec<f32>)>> {
        self.load_setting("equalizer").await
    }

    pub async fn save_effect(&mut self, id: &str, enabled: bool, params: &[f32]) -> DbResult<()> {
        self.save_setting(&format!("effect_{}", id), &(enabled, params))
            .await
    }

    pub async fn load_effect(&mut self, id: &str) -> DbResult<Option<(bool, Vec<f32>)>> {
        self.load_setting(&format!("effect_{}", id)).await
    }

    pub async fn save_setting<T: serde::Serialize>(
        &mut self,
        key: &str,
        value: &T,
    ) -> DbResult<()> {
        match serde_json::to_string(value) {
            Ok(val) => self.save_app_setting(key, &val).await,
            Err(e) => {
                tracing::error!("Failed to serialize setting '{}': {}", key, e);
                Ok(())
            }
        }
    }

    pub async fn load_setting<T: serde::de::DeserializeOwned>(
        &mut self,
        key: &str,
    ) -> DbResult<Option<T>> {
        let val = self.load_app_setting(key).await?;
        match val {
            Some(v) => match serde_json::from_str(&v) {
                Ok(parsed) => Ok(Some(parsed)),
                Err(e) => {
                    tracing::warn!("Failed to parse setting '{}': {}", key, e);
                    Ok(None)
                }
            },
            None => Ok(None),
        }
    }

    pub async fn load_all_settings(&mut self) -> DbResult<HashMap<String, String>> {
        // Full-table scan at startup: keep off the async executor.
        tokio::task::block_in_place(|| {
            // One-off repair: the column was nullable until now and the toasty
            // import copies `value` verbatim, so a NULL row is reachable.
            let _ = self
                .conn
                .execute("UPDATE app_settings SET value = '' WHERE value IS NULL", []);

            let mut stmt = self.conn.prepare("SELECT key, value FROM app_settings")?;
            let map: HashMap<String, String> = stmt
                .query_map([], |row| {
                    // Tolerant reads: a single NULL must never fail the whole
                    // query and silently reset *every* setting to its default.
                    rusqlite::Result::Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, Option<String>>(1)?.unwrap_or_default(),
                    ))
                })?
                .collect::<rusqlite::Result<Vec<_>>>()?
                .into_iter()
                .collect();
            Ok(map)
        })
    }

    pub async fn save_app_setting(&mut self, key: &str, value: &str) -> DbResult<()> {
        self.conn.execute(
            "INSERT INTO app_settings (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            params![key, value],
        )?;
        Ok(())
    }

    async fn load_app_setting(&mut self, key: &str) -> DbResult<Option<String>> {
        Ok(self
            .conn
            .query_row(
                "SELECT value FROM app_settings WHERE key = ?1",
                params![key],
                // Tolerant of a legacy NULL row instead of erroring out.
                |r| r.get::<_, Option<String>>(0).map(|v| v.unwrap_or_default()),
            )
            .optional()?)
    }
}
