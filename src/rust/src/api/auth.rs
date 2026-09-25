use crate::api::models::{AppError, SavedStateDto, UserAccountDto};
use crate::app::{AppContext, initialize_app, initialize_infrastructure};
use crate::audio::commands::AudioMessage;
use crate::auth::TokenProvider;
use crate::http::ApiService;
use flutter_rust_bridge::frb;
use std::sync::Mutex;
use std::time::Instant;

/// Minimum gap between background account refreshes.
const ACCOUNT_REFRESH_INTERVAL: std::time::Duration = std::time::Duration::from_secs(60);

/// `None` = no refresh running, `Some(at)` = last one finished at `at`.
static LAST_ACCOUNT_REFRESH: Mutex<Option<Instant>> = Mutex::new(None);

/// Claim the right to run a background account refresh, if the last one is old
/// enough. Prevents a refresh storm from repeated UI reads.
fn try_begin_account_refresh() -> bool {
    let Ok(mut last) = LAST_ACCOUNT_REFRESH.lock() else {
        return false;
    };
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
    initialize_infrastructure(None);
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

/// Tear the current session down: stop the audio system, tell every
/// shutdown-aware worker to exit, and forget the token.
pub async fn clear_token(ctx: Option<AppContext>) {
    if let Some(ctx) = &ctx {
        // Explicit, because `Drop for AppContextInner` can never run: the
        // workers and the taskbar/hotkey statics each hold a clone, and those
        // are exactly the components waiting on `shutdown_rx`.
        let _ = ctx.audio.tx.send(AudioMessage::Stop).await;
        ctx.begin_shutdown();
    }
    if let Err(e) = TokenProvider::delete().await {
        tracing::error!("Failed to delete auth token: {:?}", e);
    }
}

pub async fn login_with_token(token: String) -> Result<AppContext, AppError> {
    let user_id = TokenProvider::validate(token.clone())
        .await
        .map_err(|_| AppError::InvalidToken)?;

    if let Err(e) = TokenProvider::store(&token, user_id).await {
        tracing::error!("Failed to store auth token during login: {:?}", e);
    }

    let api = ApiService::new(token, Some(user_id))
        .await
        .map_err(|e| AppError::ApiError(e.to_string()))?;

    initialize_app(api)
        .await
        .map_err(|e| AppError::Unknown(e.to_string()))
}

pub async fn try_auto_login() -> Option<AppContext> {
    let (token, user_id) = TokenProvider::resolve().await?;

    // Fast path: bypass token validation on auto-login to speed up startup.
    if let Ok(api) = ApiService::new(token.clone(), Some(user_id)).await
        && let Ok(ctx) = initialize_app(api).await
    {
        return Some(ctx);
    }

    // Fallback if the fast path fails for any reason
    login_with_token(token).await.ok()
}

#[frb]
pub async fn get_account_info(ctx: &AppContext) -> Option<UserAccountDto> {
    // 1. Try to get from cache for instant start
    let cached: Option<UserAccountDto> = {
        let mut db = ctx.core.db.lock().await;
        db.load_setting("account_info").await.ok().flatten()
    };

    if let Some(account) = cached {
        // Return cached immediately, but refresh in the background — at most
        // one refresh per `ACCOUNT_REFRESH_INTERVAL`. Without the guard every
        // call (each Flutter navigation, each rebuild that re-reads the
        // account) spawned two HTTP requests, and `api.music.yandex.net` is
        // quick to rate-limit.
        if try_begin_account_refresh() {
            let ctx_clone = ctx.clone();
            tokio::spawn(async move {
                let result = ctx_clone.core.api.get_account_info().await;
                // Release the gate even on failure, but only after the
                // interval has elapsed (checked by `try_begin_account_refresh`).
                match result {
                    Ok(fresh) => {
                        let mut db = ctx_clone.core.db.lock().await;
                        if let Err(e) = db.save_setting("account_info", &fresh).await {
                            tracing::error!("Failed to cache account info: {:?}", e);
                        }
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
            let mut db = ctx.core.db.lock().await;
            if let Err(e) = db.save_setting("account_info", &account).await {
                tracing::error!("Failed to cache account info: {:?}", e);
            }
            Some(account)
        }
        Err(e) => {
            tracing::error!("Failed to fetch account info: {:?}", e);
            None
        }
    }
}
