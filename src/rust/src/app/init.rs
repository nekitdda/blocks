use crate::app::AUDIO_READY;
use crate::app::context::AppContext;
use crate::app::settings::load_persisted_settings;
use crate::app::workers;
use crate::audio::system::AudioSystem;
use crate::db::AppDatabase;
use crate::http::ApiService;
use crate::storage::cache::{HttpCache, TrackCache};
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::OnceLock;
use tokio::sync::Mutex;

static DATA_DIR: OnceLock<PathBuf> = OnceLock::new();
static DATABASE: tokio::sync::OnceCell<Arc<Mutex<AppDatabase>>> =
    tokio::sync::OnceCell::const_new();

pub async fn get_database()
-> Result<Arc<Mutex<AppDatabase>>, Box<dyn std::error::Error + Send + Sync>> {
    let database = DATABASE
        .get_or_try_init(|| async {
            Ok::<_, Box<dyn std::error::Error + Send + Sync>>(Arc::new(Mutex::new(
                AppDatabase::init(DATA_DIR.get().cloned()).await?,
            )))
        })
        .await?;
    Ok(database.clone())
}

pub fn get_data_dir() -> Option<PathBuf> {
    DATA_DIR.get().cloned()
}

/// Directory holding the device database and the `accounts/` tree. Mirrors
/// the fallback `AppDatabase::init` uses when Flutter passed no base path.
pub fn data_root() -> PathBuf {
    if let Some(path) = DATA_DIR.get() {
        return path.clone();
    }
    directories::ProjectDirs::from("com", "yamusic", "yamusic")
        .map(|dirs| dirs.data_dir().to_path_buf())
        .unwrap_or_default()
}

/// Private storage of one account: its database and downloaded tracks.
pub fn account_dir(uid: u64) -> PathBuf {
    data_root().join("accounts").join(uid.to_string())
}

/// Starts a session for `account_uid`: its own audio engine, database, track
/// cache and background workers. Only one session runs at a time; close the
/// previous one with `AppContext::shutdown` first.
pub async fn initialize_session(
    api: ApiService,
    account_uid: u64,
) -> Result<AppContext, Box<dyn std::error::Error + Send + Sync>> {
    initialize_services(api, account_uid).await
}

/// Initialize base infrastructure (logging, panic hook, DB)
/// Called once at FRB startup
pub fn initialize_infrastructure(base_path: Option<String>) {
    if let Some(path) = base_path {
        let p = PathBuf::from(path);
        std::fs::create_dir_all(&p).ok();
        DATA_DIR.set(p).ok();
    }

    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        flutter_rust_bridge::setup_default_user_utils();
        crate::util::hook::set_panic_hook();
        let _ = crate::util::log::initialize_logging();
    });
}

async fn initialize_services(
    api: ApiService,
    account_uid: u64,
) -> Result<AppContext, Box<dyn std::error::Error + Send + Sync>> {
    let api_arc = Arc::new(api);
    let event_sink: Arc<
        tokio::sync::OnceCell<crate::frb_generated::StreamSink<crate::api::simple::AppEvent>>,
    > = Arc::new(tokio::sync::OnceCell::new());
    let error_reporter: Arc<dyn Fn(String) + Send + Sync> = {
        let event_sink = event_sink.clone();
        Arc::new(move |msg| {
            if let Some(sink) = event_sink.get() {
                let _ = sink.add(crate::api::simple::AppEvent::Error(msg));
            }
        })
    };

    let device_db = get_database().await?;
    let account_path = account_dir(account_uid);
    let account_db = Arc::new(Mutex::new(AppDatabase::open_account(&account_path).await?));
    // Image cache is keyed by URL and shared; downloads belong to the account.
    let http_cache = Arc::new(HttpCache::new(device_db.clone(), DATA_DIR.get().cloned()));
    let track_cache = Arc::new(TrackCache::new(Some(account_path)));
    let _ = track_cache.init().await;

    let (audio_tx, signals, state, effect_handles) = AudioSystem::spawn(
        error_reporter,
        api_arc.clone(),
        account_db.clone(),
        device_db.clone(),
        http_cache.clone(),
        track_cache.clone(),
    )
    .await?;

    let (context, shutdown_rx) = AppContext::new(crate::app::context::SessionParts {
        audio_tx,
        api: api_arc.clone(),
        db: account_db,
        device_db,
        http_cache,
        track_cache,
        signals: signals.clone(),
        state,
        effect_handles: effect_handles.clone(),
        event_sink,
        account_uid,
    });

    load_persisted_settings(&context).await;
    context.audio.signals.monitor.set_enabled(true);

    workers::spawn_sync_worker(context.clone(), shutdown_rx.clone());
    workers::spawn_bridge_worker(context.clone(), shutdown_rx.clone());
    workers::spawn_settings_worker(context.clone(), shutdown_rx.clone());
    workers::spawn_cache_worker(context.clone(), shutdown_rx.clone());

    #[cfg(target_os = "windows")]
    crate::audio::taskbar::init(context.clone(), shutdown_rx.clone());

    // macOS requires the manager to live on the main thread (see
    // app/hotkeys.rs); the app doesn't ship for macOS, so gate it out.
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    crate::app::hotkeys::init(context.clone(), shutdown_rx.clone()).await;

    AUDIO_READY.notify_waiters();
    Ok(context)
}
