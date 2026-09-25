//! Registry of the Yandex accounts signed in on this device.
//!
//! Tokens and cached profiles live in the device database; everything that
//! belongs to one account (library cache, listening history, playback state,
//! listening preferences, downloaded tracks) lives under `accounts/<uid>/`,
//! so sessions never share state and removing an account removes its data.

use crate::app::init::data_root;
use crate::db::{AppDatabase, StoredAccount};
use std::path::{Path, PathBuf};
use yandex_music::YandexMusicClient;

type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

fn account_dir_in(root: &Path, uid: u64) -> PathBuf {
    root.join("accounts").join(uid.to_string())
}

pub struct AccountStore;

impl AccountStore {
    pub async fn list() -> Result<Vec<StoredAccount>> {
        let database = crate::app::get_database().await?;
        let mut db = database.lock().await;
        Ok(db.list_accounts().await?)
    }

    pub async fn get(uid: u64) -> Result<Option<StoredAccount>> {
        let database = crate::app::get_database().await?;
        let mut db = database.lock().await;
        Ok(db.get_account(uid).await?)
    }

    pub async fn active_uid() -> Option<u64> {
        let database = crate::app::get_database().await.ok()?;
        let mut db = database.lock().await;
        db.load_active_account_uid().await.ok().flatten()
    }

    pub async fn save_token(uid: u64, token: &str) -> Result<()> {
        let database = crate::app::get_database().await?;
        let mut db = database.lock().await;
        db.save_account_token(uid, token).await?;
        Ok(())
    }

    pub async fn save_profile(profile: &crate::api::models::UserAccountDto) -> Result<()> {
        let database = crate::app::get_database().await?;
        let mut db = database.lock().await;
        db.save_account_profile(profile).await?;
        Ok(())
    }

    pub async fn mark_active(uid: u64) -> Result<()> {
        let database = crate::app::get_database().await?;
        let mut db = database.lock().await;
        db.mark_account_active(uid).await?;
        Ok(())
    }

    /// The server rejected the token: forget it but keep the account listed.
    pub async fn mark_expired(uid: u64) -> Result<()> {
        let database = crate::app::get_database().await?;
        let mut db = database.lock().await;
        db.clear_account_token(uid).await?;
        Ok(())
    }

    /// Forgets the account and deletes its local data. The session must be
    /// closed first so the account database is no longer open.
    pub async fn remove(uid: u64) -> Result<()> {
        let database = crate::app::get_database().await?;
        let mut db = database.lock().await;
        db.delete_account(uid).await?;

        let dir = account_dir_in(&data_root(), uid);
        if let Err(e) = remove_dir_if_exists(&dir).await {
            // Retried on the next start, before any session opens a file there.
            tracing::warn!("Deferring removal of {:?}: {}", dir, e);
            let mut pending = db.load_pending_account_cleanup().await.unwrap_or_default();
            if !pending.contains(&uid) {
                pending.push(uid);
            }
            db.save_pending_account_cleanup(&pending).await?;
        }
        Ok(())
    }

    /// Picks the account to open on launch: the last active one if it still
    /// has a token, otherwise the most recently used account with a token.
    pub async fn startup_account() -> Option<StoredAccount> {
        let database = crate::app::get_database().await.ok()?;
        let mut db = database.lock().await;
        let root = data_root();

        if let Err(e) = run_pending_cleanup(&mut db, &root).await {
            tracing::warn!("Account cleanup failed: {:?}", e);
        }
        if let Err(e) = migrate_single_account_install(&mut db, &root).await {
            tracing::error!("Single-account migration failed: {:?}", e);
        }

        pick_startup_account(&mut db).await
    }
}

async fn pick_startup_account(db: &mut AppDatabase) -> Option<StoredAccount> {
    let accounts = db.list_accounts().await.ok()?;
    let active = db.load_active_account_uid().await.ok().flatten();
    let mut usable: Vec<StoredAccount> =
        accounts.into_iter().filter(|a| !a.token.is_empty()).collect();
    if let Some(uid) = active
        && let Some(pos) = usable.iter().position(|a| a.uid == uid)
    {
        return Some(usable.swap_remove(pos));
    }
    usable.into_iter().max_by_key(|a| a.last_active_at)
}

/// Returns the uid the token belongs to, or an error if Yandex rejects it.
pub async fn validate_token(token: &str) -> Result<u64> {
    let client = YandexMusicClient::builder(token).build()?;
    let status = client.get_account_status().await?;
    status.account.uid.ok_or_else(|| "No user id found".into())
}

async fn remove_dir_if_exists(dir: &Path) -> std::io::Result<()> {
    match tokio::fs::remove_dir_all(dir).await {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e),
    }
}

async fn run_pending_cleanup(db: &mut AppDatabase, root: &Path) -> Result<()> {
    let pending = db.load_pending_account_cleanup().await?;
    if pending.is_empty() {
        return Ok(());
    }
    let mut still_pending = Vec::new();
    for uid in pending {
        // The user may have signed back in before the retry.
        if db.get_account(uid).await?.is_some() {
            continue;
        }
        if remove_dir_if_exists(&account_dir_in(root, uid)).await.is_err() {
            still_pending.push(uid);
        }
    }
    db.save_pending_account_cleanup(&still_pending).await?;
    Ok(())
}

/// Before multi-account support the device database held the only token
/// (`auth_token`) next to that account's library and preferences, and
/// downloads lived in `offline_tracks/`. Move all of it into the account's
/// own directory. The legacy token is deleted last, so an interrupted
/// migration is retried (every step is idempotent).
async fn migrate_single_account_install(db: &mut AppDatabase, root: &Path) -> Result<()> {
    let Some((token, uid)) = db.load_auth_token().await? else {
        // Leftovers of a signed-out single-account install belong to nobody.
        if db.list_accounts().await?.is_empty() {
            db.purge_legacy_account_data().await?;
        }
        return Ok(());
    };

    let dir = account_dir_in(root, uid);
    {
        let mut account_db = AppDatabase::open_account(&dir).await?;
        account_db.import_legacy_account_data(db.path()).await?;
        account_db.close();
    }
    move_legacy_downloads(&root.join("offline_tracks"), &dir.join("offline_tracks")).await;

    if db.get_account(uid).await?.is_none() {
        db.save_account_token(uid, &token).await?;
    }
    if db.load_active_account_uid().await?.is_none() {
        db.mark_account_active(uid).await?;
    }
    db.purge_legacy_account_data().await?;
    db.delete_auth_token().await?;
    tracing::info!("Migrated single-account data to {:?}", dir);
    Ok(())
}

async fn move_legacy_downloads(from: &Path, to: &Path) {
    if tokio::fs::metadata(from).await.is_err() {
        return;
    }
    if tokio::fs::metadata(to).await.is_err() {
        if let Some(parent) = to.parent() {
            let _ = tokio::fs::create_dir_all(parent).await;
        }
        if tokio::fs::rename(from, to).await.is_ok() {
            return;
        }
    }
    // Target exists (or rename crossed devices): move entry by entry.
    let _ = tokio::fs::create_dir_all(to).await;
    let Ok(mut entries) = tokio::fs::read_dir(from).await else {
        return;
    };
    while let Ok(Some(entry)) = entries.next_entry().await {
        let target = to.join(entry.file_name());
        if tokio::fs::metadata(&target).await.is_ok() {
            continue;
        }
        if tokio::fs::rename(entry.path(), &target).await.is_err()
            && tokio::fs::copy(entry.path(), &target).await.is_ok()
        {
            let _ = tokio::fs::remove_file(entry.path()).await;
        }
    }
    let _ = tokio::fs::remove_dir(from).await;
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::models::UserAccountDto;

    fn temp_root(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "youmuz-test-{name}-{}-{}",
            std::process::id(),
            chrono::Utc::now().timestamp_nanos_opt().unwrap_or_default()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn profile(uid: i64, login: &str) -> UserAccountDto {
        UserAccountDto {
            uid,
            login: login.into(),
            full_name: Some(format!("{login} full")),
            display_name: Some(login.to_uppercase()),
            has_plus: uid % 2 == 0,
            avatar_url: None,
        }
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn registry_keeps_accounts_and_active_selection() {
        let root = temp_root("registry");
        let mut db = AppDatabase::init(Some(root.clone())).await.unwrap();

        db.save_account_token(10, "token-a").await.unwrap();
        db.save_account_token(20, "token-b").await.unwrap();
        db.save_account_profile(&profile(10, "anna")).await.unwrap();
        db.save_account_profile(&profile(20, "boris")).await.unwrap();
        db.mark_account_active(20).await.unwrap();

        let accounts = db.list_accounts().await.unwrap();
        assert_eq!(accounts.iter().map(|a| a.uid).collect::<Vec<_>>(), vec![10, 20]);
        assert_eq!(accounts[0].login, "anna");
        assert!(accounts[1].has_plus);
        assert_eq!(db.load_active_account_uid().await.unwrap(), Some(20));
        assert_eq!(pick_startup_account(&mut db).await.unwrap().uid, 20);

        // Re-adding an account refreshes the token but keeps its position.
        db.save_account_token(10, "token-a2").await.unwrap();
        let first = db.get_account(10).await.unwrap().unwrap();
        assert_eq!(first.token, "token-a2");
        assert_eq!(db.list_accounts().await.unwrap()[0].uid, 10);

        // An expired account is skipped at startup but stays listed.
        db.clear_account_token(20).await.unwrap();
        assert_eq!(pick_startup_account(&mut db).await.unwrap().uid, 10);
        assert_eq!(db.list_accounts().await.unwrap().len(), 2);

        // Removing the active account clears the selection.
        db.mark_account_active(20).await.unwrap();
        db.delete_account(20).await.unwrap();
        assert_eq!(db.load_active_account_uid().await.unwrap(), None);
        assert_eq!(db.list_accounts().await.unwrap().len(), 1);
        let _ = std::fs::remove_dir_all(root);
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn account_databases_do_not_share_state() {
        let root = temp_root("isolation");
        let mut a = AppDatabase::open_account(&account_dir_in(&root, 1)).await.unwrap();
        let mut b = AppDatabase::open_account(&account_dir_in(&root, 2)).await.unwrap();

        a.save_liked_tracks(&["100".into(), "101".into()]).await.unwrap();
        a.save_setting("audio_quality", &"High").await.unwrap();
        a.save_playback_state("100", 42_000, false).await.unwrap();
        b.add_liked_track("200").await.unwrap();

        assert_eq!(b.load_liked_tracks().await.unwrap(), vec!["200".to_string()]);
        assert_eq!(b.load_setting::<String>("audio_quality").await.unwrap(), None);
        assert_eq!(b.load_playback_state().await.unwrap(), None);
        let mut liked_a = a.load_liked_tracks().await.unwrap();
        liked_a.sort();
        assert_eq!(liked_a, vec!["100".to_string(), "101".to_string()]);
        assert_eq!(
            a.load_playback_state().await.unwrap(),
            Some(("100".to_string(), 42_000, false))
        );

        // Closing releases the file so the directory can be removed.
        a.close();
        b.close();
        std::fs::remove_dir_all(account_dir_in(&root, 1)).unwrap();
        let _ = std::fs::remove_dir_all(root);
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn listening_history_is_ordered_and_bounded() {
        let root = temp_root("history");
        let mut db = AppDatabase::open_account(&account_dir_in(&root, 3)).await.unwrap();
        for i in 0..105u64 {
            db.record_played_track(crate::db::TrackMetadata {
                id: format!("t{i}"),
                title: format!("Track {i}"),
                version: None,
                artists: vec![crate::api::models::TrackArtistDto {
                    id: "7".into(),
                    name: "Artist".into(),
                }],
                album: None,
                album_id: None,
                cover_url: None,
                duration_ms: 1000,
            })
            .await
            .unwrap();
            // Distinct timestamps for a deterministic order.
            tokio::time::sleep(std::time::Duration::from_millis(2)).await;
        }
        let recent = db.load_play_history(200).await.unwrap();
        assert_eq!(recent.len(), 100);
        assert_eq!(recent[0].id, "t104");
        assert_eq!(recent[0].artists[0].name, "Artist");
        assert_eq!(recent.last().unwrap().id, "t5");
        db.close();
        let _ = std::fs::remove_dir_all(root);
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn single_account_install_is_migrated() {
        let root = temp_root("migration");
        let mut device = AppDatabase::init(Some(root.clone())).await.unwrap();
        device.save_auth_token("legacy-token", 77).await.unwrap();
        device.save_liked_tracks(&["1".into(), "2".into()]).await.unwrap();
        device.save_setting("equalizer", &(true, vec![1.0f32, 2.0])).await.unwrap();
        device.save_setting("effect_reverb", &(true, vec![0.5f32])).await.unwrap();
        device.save_setting("playback_state", &("2".to_string(), 5u64, true)).await.unwrap();
        device.save_setting("custom_titlebar", &false).await.unwrap();
        device.save_setting("volume", &55u8).await.unwrap();
        std::fs::create_dir_all(root.join("offline_tracks")).unwrap();
        std::fs::write(root.join("offline_tracks").join("2.flac"), b"audio").unwrap();

        migrate_single_account_install(&mut device, &root).await.unwrap();

        // Token moved into the registry, account selected, legacy key gone.
        assert_eq!(device.load_auth_token().await.unwrap(), None);
        assert_eq!(device.get_account(77).await.unwrap().unwrap().token, "legacy-token");
        assert_eq!(device.load_active_account_uid().await.unwrap(), Some(77));
        // Device keeps device settings only.
        assert_eq!(device.load_setting::<bool>("custom_titlebar").await.unwrap(), Some(false));
        assert_eq!(device.load_setting::<u8>("volume").await.unwrap(), Some(55));
        assert!(device.load_liked_tracks().await.unwrap().is_empty());
        assert_eq!(device.load_equalizer().await.unwrap(), None);
        assert_eq!(device.load_effect("reverb").await.unwrap(), None);

        let dir = account_dir_in(&root, 77);
        let mut account = AppDatabase::open_account(&dir).await.unwrap();
        let mut liked = account.load_liked_tracks().await.unwrap();
        liked.sort();
        assert_eq!(liked, vec!["1".to_string(), "2".to_string()]);
        assert_eq!(account.load_equalizer().await.unwrap(), Some((true, vec![1.0, 2.0])));
        assert_eq!(account.load_effect("reverb").await.unwrap(), Some((true, vec![0.5])));
        assert_eq!(
            account.load_playback_state().await.unwrap(),
            Some(("2".to_string(), 5, true))
        );
        assert_eq!(account.load_setting::<bool>("custom_titlebar").await.unwrap(), None);
        assert!(dir.join("offline_tracks").join("2.flac").exists());
        assert!(!root.join("offline_tracks").exists());

        // Running again is a no-op.
        migrate_single_account_install(&mut device, &root).await.unwrap();
        assert_eq!(device.list_accounts().await.unwrap().len(), 1);
        account.close();
        let _ = std::fs::remove_dir_all(root);
    }
}
