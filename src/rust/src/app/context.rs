use crate::api::simple::AppEvent;
use crate::audio::commands::AudioMessage;
use crate::audio::fx::EffectHandle;
use crate::audio::signals::AudioSignals;
use crate::audio::state::SystemState;
use crate::db::AppDatabase;
use crate::frb_generated::StreamSink;
use crate::http::ApiService;
use crate::storage::cache::{HttpCache, TrackCache};
use foldhash::HashMap;
use parking_lot::RwLock as StdRwLock;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{Mutex, Notify, OnceCell, RwLock, mpsc, watch};

/// Upper bound for the audio actor to stop when a session closes.
const AUDIO_SHUTDOWN_TIMEOUT: Duration = Duration::from_secs(5);

pub struct AppAudioContext {
    pub tx: mpsc::Sender<AudioMessage>,
    pub signals: AudioSignals,
    pub state: Arc<RwLock<SystemState>>,
    pub effect_handles: Arc<StdRwLock<HashMap<String, EffectHandle>>>,
}

pub struct AppCoreContext {
    pub api: Arc<ApiService>,
    /// Database of the signed-in account: library cache, listening history,
    /// playback state and listening preferences.
    pub db: Arc<Mutex<AppDatabase>>,
    /// Device database: account registry, window/tray/hotkey/volume settings
    /// and the image cache index. Shared by every session.
    pub device_db: Arc<Mutex<AppDatabase>>,
    pub http_cache: Arc<HttpCache>,
    pub track_cache: Arc<TrackCache>,
    pub account_uid: u64,
    /// Last background account refresh, to avoid a refresh storm.
    pub account_refresh: parking_lot::Mutex<Option<Instant>>,
}

pub struct AppSystemContext {
    pub event_sink: Arc<OnceCell<StreamSink<AppEvent>>>,
    pub shutdown_tx: watch::Sender<bool>,
}

pub struct AppContextInner {
    pub audio: AppAudioContext,
    pub core: AppCoreContext,
    pub system: AppSystemContext,
}

#[derive(Clone)]
pub struct AppContext {
    inner: Arc<AppContextInner>,
}

/// Everything `initialize_session` assembles for a new session.
pub struct SessionParts {
    pub audio_tx: mpsc::Sender<AudioMessage>,
    pub api: Arc<ApiService>,
    pub db: Arc<Mutex<AppDatabase>>,
    pub device_db: Arc<Mutex<AppDatabase>>,
    pub http_cache: Arc<HttpCache>,
    pub track_cache: Arc<TrackCache>,
    pub signals: AudioSignals,
    pub state: Arc<RwLock<SystemState>>,
    pub effect_handles: Arc<StdRwLock<HashMap<String, EffectHandle>>>,
    pub event_sink: Arc<OnceCell<StreamSink<AppEvent>>>,
    pub account_uid: u64,
}

impl AppContext {
    pub fn new(parts: SessionParts) -> (Self, watch::Receiver<bool>) {
        let (shutdown_tx, shutdown_rx) = watch::channel(false);
        let inner = Arc::new(AppContextInner {
            audio: AppAudioContext {
                tx: parts.audio_tx,
                signals: parts.signals,
                state: parts.state,
                effect_handles: parts.effect_handles,
            },
            core: AppCoreContext {
                api: parts.api,
                db: parts.db,
                device_db: parts.device_db,
                http_cache: parts.http_cache,
                track_cache: parts.track_cache,
                account_uid: parts.account_uid,
                account_refresh: parking_lot::Mutex::new(None),
            },
            system: AppSystemContext {
                event_sink: parts.event_sink,
                shutdown_tx,
            },
        });
        (Self { inner }, shutdown_rx)
    }

    pub fn send_event(&self, event: AppEvent) {
        if let Some(sink) = self.inner.system.event_sink.get() {
            let _ = sink.add(event);
        }
    }

    /// Signal every shutdown-aware worker/task to stop.
    ///
    /// `Drop for AppContextInner` does the same thing, but it can never fire:
    /// `initialize_services` clones the context into the workers, the taskbar
    /// watcher and the hotkey statics, and those components are exactly the
    /// ones waiting on `shutdown_rx`. The last clone can only be released once
    /// they are gone, so the shutdown signal would never be delivered. Call
    /// this explicitly from the teardown path instead of relying on `Drop`.
    pub fn begin_shutdown(&self) {
        let _ = self.inner.system.shutdown_tx.send(true);
    }

    /// True when both handles belong to the same session.
    pub fn same_session(&self, other: &AppContext) -> bool {
        Arc::ptr_eq(&self.inner, &other.inner)
    }

    /// Ends the session: pauses playback, stores where the account left off,
    /// stops every worker and the audio actor (releasing the output device and
    /// media-session integration) and closes the account database. The next
    /// session can start as soon as this returns.
    pub async fn shutdown(&self) {
        let _ = self.audio.tx.send(AudioMessage::Pause).await;
        self.begin_shutdown();

        let done = Arc::new(Notify::new());
        if self
            .audio
            .tx
            .send(AudioMessage::Shutdown(done.clone()))
            .await
            .is_ok()
            && tokio::time::timeout(AUDIO_SHUTDOWN_TIMEOUT, done.notified())
                .await
                .is_err()
        {
            tracing::warn!("Audio system did not stop in time");
        }

        // Written after the actor stopped, so nothing can overwrite it.
        let mut db = self.core.db.lock().await;
        if let Some(track_id) = self.audio.signals.current_track_id.get() {
            let position_ms = self.audio.signals.position_ms.get();
            if let Err(e) = db.save_playback_state(&track_id, position_ms, false).await {
                tracing::error!("Failed to save playback state: {:?}", e);
            }
        }
        db.close();
    }
}

impl std::ops::Deref for AppContext {
    type Target = AppContextInner;

    fn deref(&self) -> &Self::Target {
        &self.inner
    }
}

impl Drop for AppContextInner {
    fn drop(&mut self) {
        let _ = self.system.shutdown_tx.send(true);
    }
}
