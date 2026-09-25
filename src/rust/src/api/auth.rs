//! Accounts and sessions.
//!
//! Several Yandex accounts can be signed in at once (like Telegram). Exactly
//! one of them has an open session (`AppContext`): its own API client, audio
//! engine, workers and database. Switching closes the current session and
//! opens another; nobody is signed out in the process.

use crate::api::models::{AppError, SavedStateDto, StoredAccountDto, UserAccountDto};
use crate::app::{AppContext, initialize_session};
use crate::auth::{AccountStore, is_network_error, validate_token};
use crate::http::ApiService;
use flutter_rust_bridge::frb;
use std::time::Instant;

/// Minimum gap between background account refreshes.
const ACCOUNT_REFRESH_INTERVAL: std::time::Duration = std::time::Duration::from_secs(60);

/// Claim the right to run a background account refresh for this session, if
/// the last one is old enough. Prevents a refresh storm from repeated UI reads.
fn try_begin_account_refresh(ctx: &AppContext) -> bool {
    let mut last = ctx.core.account_refresh.lock();
    if let Some(at) = *last
        && at.elapsed() < ACCOUNT_REFRESH_INTERVAL
    {
        return false;
    }
    // Mark now: the slot is held for the interval regardless of the outcome.
    *last = Some(Instant::now());
    true
}

#[frb(init)]
pub fn init_app() {
    crate::app::initialize_infrastructure(None);
}

pub async fn restore_saved_state(ctx: &AppContext) -> Option<SavedStateDto> {
    let mut db = ctx.core.db.lock().await;
    db.load_playback_state()
        .await
        .ok()
        .flatten()
        .map(|(id, pos, playing)| SavedStateDto {
            track_id: id,
            position_ms: pos as u32,
            is_playing: playing,
        })
}

/// All accounts signed in on this device, in the order they were added.
pub async fn list_accounts() -> Vec<StoredAccountDto> {
    let active = AccountStore::active_uid().await;
    match AccountStore::list().await {
        Ok(accounts) => accounts
            .into_iter()
            .map(|a| StoredAccountDto::from_stored(a, active))
            .collect(),
        Err(e) => {
            tracing::error!("Failed to list accounts: {:?}", e);
            Vec::new()
        }
    }
}

/// Validates the token and remembers the account. Does not touch the open
/// session: the caller switches to the account afterwards. Signing in to an
/// account that is already listed refreshes its token.
pub async fn add_account(token: String) -> Result<StoredAccountDto, AppError> {
    let token = token.trim().to_string();
    let uid = validate_token(&token).await.map_err(|e| {
        if is_network_error(e.as_ref()) {
            AppError::NetworkError
        } else {
            AppError::InvalidToken
        }
    })?;

    AccountStore::save_token(uid, &token).await?;

    // The profile only feeds the account switcher; a network hiccup here must
    // not fail the sign-in (it is refreshed when the session opens).
    match ApiService::new(token, Some(uid)).await {
        Ok(api) => match api.get_account_info().await {
            Ok(profile) => {
                if let Err(e) = AccountStore::save_profile(&profile).await {
                    tracing::error!("Failed to store account profile: {:?}", e);
                }
            }
            Err(e) => tracing::warn!("Failed to fetch profile of new account: {:?}", e),
        },
        Err(e) => tracing::warn!("Failed to create client for new account: {:?}", e),
    }

    let active = AccountStore::active_uid().await;
    let stored = AccountStore::get(uid)
        .await?
        .ok_or_else(|| AppError::DbError("account was not saved".into()))?;
    Ok(StoredAccountDto::from_stored(stored, active))
}

/// Opens a session for a stored account and makes it the active one. Close
/// the previous session (`close_session`) before calling this.
pub async fn open_account_session(uid: i64) -> Result<AppContext, AppError> {
    let uid = u64::try_from(uid).map_err(|_| AppError::NotFound(uid.to_string()))?;
    let account = AccountStore::get(uid)
        .await?
        .ok_or_else(|| AppError::NotFound(format!("account {uid}")))?;
    if account.token.is_empty() {
        return Err(AppError::Unauthorized);
    }

    // No token validation here, to keep startup and switching fast: a revoked
    // token surfaces as `Unauthorized` on the first request.
    let api = ApiService::new(account.token, Some(uid))
        .await
        .map_err(|e| AppError::ApiError(e.to_string()))?;
    let ctx = initialize_session(api, uid)
        .await
        .map_err(|e| AppError::Unknown(e.to_string()))?;
    AccountStore::mark_active(uid).await?;
    Ok(ctx)
}

/// Opens the session of the account used last. `None` shows the sign-in screen.
pub async fn try_auto_login() -> Option<AppContext> {
    let account = AccountStore::startup_account().await?;
    match open_account_session(account.uid as i64).await {
        Ok(ctx) => Some(ctx),
        Err(e) => {
            tracing::error!("Failed to restore session of {}: {:?}", account.uid, e);
            None
        }
    }
}

/// Ends the session without signing the account out: playback stops, the
/// position is remembered and the audio device is released.
pub async fn close_session(ctx: &AppContext) {
    ctx.shutdown().await;
}

/// Signs the account out on this device and deletes its local data (library
/// cache, history, preferences, downloads). Close its session first.
pub async fn remove_account(uid: i64) -> Result<(), AppError> {
    let uid = u64::try_from(uid).map_err(|_| AppError::NotFound(uid.to_string()))?;
    AccountStore::remove(uid).await?;
    Ok(())
}

/// The server rejected the account's token. The account stays in the list
/// (with its local data) until the user signs in again or removes it.
pub async fn mark_account_needs_login(uid: i64) -> Result<(), AppError> {
    let uid = u64::try_from(uid).map_err(|_| AppError::NotFound(uid.to_string()))?;
    AccountStore::mark_expired(uid).await?;
    Ok(())
}

#[frb(sync)]
pub fn session_account_uid(ctx: &AppContext) -> i64 {
    ctx.core.account_uid as i64
}

#[frb]
pub async fn get_account_info(ctx: &AppContext) -> Option<UserAccountDto> {
    // 1. Try to get from cache for instant start
    let cached: Option<UserAccountDto> = {
        let mut db = ctx.core.db.lock().await;
        db.load_setting("account_info").await.ok().flatten()
    };

    if let Some(account) = cached {
        // Keeps the switcher entry named even before the first online refresh
        // (e.g. right after migrating a single-account install, or offline).
        if let Err(e) = AccountStore::save_profile(&account).await {
            tracing::warn!("Failed to sync cached profile to the registry: {:?}", e);
        }
        // Return cached immediately, but refresh in the background — at most
        // one refresh per `ACCOUNT_REFRESH_INTERVAL`. Without the guard every
        // call (each Flutter navigation, each rebuild that re-reads the
        // account) spawned two HTTP requests, and `api.music.yandex.net` is
        // quick to rate-limit.
        if try_begin_account_refresh(ctx) {
            let ctx_clone = ctx.clone();
            tokio::spawn(async move {
                match ctx_clone.core.api.get_account_info().await {
                    Ok(fresh) => {
                        store_account_info(&ctx_clone, &fresh).await;
                        ctx_clone.send_event(crate::api::simple::AppEvent::AccountUpdated(fresh));
                    }
                    Err(e) => {
                        tracing::error!("Failed to refresh account info: {:?}", e);
                    }
                }
            });
        }
        return Some(account);
    }

    // 2. If no cache, wait for API
    match ctx.core.api.get_account_info().await {
        Ok(account) => {
            store_account_info(ctx, &account).await;
            Some(account)
        }
        Err(e) => {
            tracing::error!("Failed to fetch account info: {:?}", e);
            None
        }
    }
}

/// Caches the profile for this session and refreshes the switcher entry.
async fn store_account_info(ctx: &AppContext, account: &UserAccountDto) {
    {
        let mut db = ctx.core.db.lock().await;
        if let Err(e) = db.save_setting("account_info", account).await {
            tracing::error!("Failed to cache account info: {:?}", e);
        }
    }
    if account.uid as u64 == ctx.core.account_uid
        && let Err(e) = AccountStore::save_profile(account).await
    {
        tracing::error!("Failed to update stored account profile: {:?}", e);
    }
}
