use crate::api::simple::AppEvent;
use crate::app::{AppContext, SETTINGS_CHANGED};
use crate::audio::commands::AudioMessage;
use tokio::sync::watch;

pub fn spawn_sync_worker(ctx: AppContext, mut shutdown_rx: watch::Receiver<bool>) {
    tokio::spawn(async move {
        let _ = ctx.audio.tx.send(AudioMessage::SyncLiked).await;

        loop {
            tokio::select! {
                _ = tokio::time::sleep(tokio::time::Duration::from_secs(300)) => {
                    let _ = ctx.audio.tx.send(AudioMessage::SyncLiked).await;
                }
                _ = shutdown_rx.changed() => {
                    if *shutdown_rx.borrow() { break; }
                }
            }
        }
    });
}

pub fn spawn_bridge_worker(ctx: AppContext, mut shutdown_rx: watch::Receiver<bool>) {
    tokio::spawn(async move {
        let audio_signals = ctx.audio.signals.clone();
        let audio_state = ctx.audio.state.clone();

        // Send initial state
        {
            let (liked, disliked) = audio_state.read().await.liked.snapshot();
            let state = crate::api::playback::get_playback_state_internal(
                &audio_signals,
                &liked,
                &disliked,
            );
            ctx.send_event(AppEvent::PlaybackStateChanged(state));

            ctx.send_event(AppEvent::PlaybackProgress(
                crate::api::models::PlaybackProgressDto {
                    position_ms: audio_signals.position_ms.get() as u32,
                    duration_ms: audio_signals.duration_ms.get() as u32,
                },
            ));
        }

        let mut changed_rx = audio_signals.changed_rx.clone();
        let mut progress_rx = audio_signals.progress_rx.clone();
        let mut vibe_interval = tokio::time::interval(tokio::time::Duration::from_millis(33));
        let mut save_interval = tokio::time::interval(tokio::time::Duration::from_secs(5));
        let mut last_saved_position_ms = 0u64;

        // Coalesced playback-state write. `changed` also fires on every
        // buffering transition (the armed `BufferingGate` drives it), so a
        // stuttering stream used to cost one Track deep-clone + DTO + FFI event
        // + `tokio::spawn` + a queued global-DB write *per stall*, all
        // redundant. Keep only the newest intent and flush it on the interval.
        let mut pending_state: Option<(String, u64, bool)> = None;
        let mut last_vibe_active = false;

        loop {
            tokio::select! {
                _ = shutdown_rx.changed() => {
                    if *shutdown_rx.borrow() {
                        // Flush whatever is still pending before exiting.
                        if let Some((track_id, position_ms, is_playing)) = pending_state.take() {
                            let mut db = ctx.core.db.lock().await;
                            let _ = db.save_playback_state(&track_id, position_ms, is_playing).await;
                        }
                        break;
                    }
                }
                res = changed_rx.changed() => {
                    if res.is_err() { break; }
                    let (liked, disliked) = audio_state.read().await.liked.snapshot();
                    let state = crate::api::playback::get_playback_state_internal(&audio_signals, &liked, &disliked);
                    ctx.send_event(AppEvent::PlaybackStateChanged(state));

                    // Record intent only; the write happens on `save_interval`.
                    if let Some(track_id) = audio_signals.current_track_id.get() {
                        pending_state = Some((
                            track_id,
                            audio_signals.position_ms.get(),
                            audio_signals.is_playing.get(),
                        ));
                    } else {
                        pending_state = None;
                    }
                }
                res = progress_rx.changed() => {
                    if res.is_err() { break; }
                    let pos = *progress_rx.borrow();
                    let dur = audio_signals.duration_ms.get();
                    ctx.send_event(AppEvent::PlaybackProgress(crate::api::models::PlaybackProgressDto {
                        position_ms: pos,
                        duration_ms: dur as u32,
                    }));
                }
                _ = vibe_interval.tick() => {
                    let is_playing = audio_signals.is_playing.get();
                    if let Ok(mut vibe) = audio_signals.monitor.vibe.try_lock() {
                        // Fetch bands only once the lock is held: vibe_bands()
                        // swaps the peaks to zero, so reading it before a failed
                        // try_lock would silently discard them.
                        let bands = audio_signals.monitor.vibe_bands();
                        vibe.set_playing(is_playing);
                        let uniforms = vibe.tick(bands);
                        // `tick` never reports "idle" — it just decays the
                        // envelopes — so an unconditional send cost 30 FFI
                        // crossings per second forever, even with the app
                        // closed to the tray and nothing playing. Gate on actual
                        // activity plus a short tail so a "like" reaction still
                        // animates out after playback stops.
                        let active = is_playing || vibe.has_energy();
                        if active || last_vibe_active {
                            ctx.send_event(AppEvent::VibeTick(uniforms));
                        }
                        last_vibe_active = active;
                    }
                }
                _ = save_interval.tick() => {
                    // Flush the coalesced playback-state write, then the periodic
                    // position checkpoint.
                    if let Some((track_id, position_ms, is_playing)) = pending_state.take() {
                        let mut db = ctx.core.db.lock().await;
                        let _ = db.save_playback_state(&track_id, position_ms, is_playing).await;
                        last_saved_position_ms = position_ms;
                    } else if audio_signals.is_playing.get() {
                        let track_id = audio_signals.current_track_id.get();
                        let position_ms = audio_signals.position_ms.get();
                        // Save only if position changed significantly (> 3 sec)
                        if let Some(track_id) = track_id
                            && position_ms.saturating_sub(last_saved_position_ms) > 3000 {
                            let mut db = ctx.core.db.lock().await;
                            let _ = db.save_playback_state(&track_id, position_ms, true).await;
                            last_saved_position_ms = position_ms;
                        }
                    }
                }
            }
        }
    });
}

pub fn spawn_settings_worker(ctx: AppContext, mut shutdown_rx: watch::Receiver<bool>) {
    tokio::spawn(async move {
        loop {
            tokio::select! {
                _ = SETTINGS_CHANGED.notified() => {
                    tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;

                    let (eq_bands, eq_enabled, effects, quality) = {
                        let guard = ctx.audio.effect_handles.read();
                        let eq = guard.get("eq");
                        let eq_bands = eq.map(|e| (0..e.param_count()).map(|i| e.get_param(i)).collect::<Vec<_>>());
                        let eq_enabled = eq.map(|e| e.is_enabled()).unwrap_or(false);

                        let mut effects = Vec::new();
                        for (id, handle) in guard.iter() {
                            if matches!(id.as_str(), "eq" | "monitor" | "fade") {
                                continue;
                            }
                            let params: Vec<_> = (0..handle.param_count()).map(|i| handle.get_param(i)).collect();
                            effects.push((id.clone(), handle.is_enabled(), params));
                        }

                        (eq_bands, eq_enabled, effects, ctx.core.api.get_quality())
                    };

                    let mut db = ctx.core.db.lock().await;

                    if let Some(bands) = eq_bands {
                        let _ = db.save_equalizer(eq_enabled, &bands).await;
                    }

                    let _ = db.save_setting("audio_quality", &quality).await;

                    for (id, enabled, params) in effects {
                        let _ = db.save_effect(&id, enabled, &params).await;
                    }
                }
                _ = shutdown_rx.changed() => {
                    if *shutdown_rx.borrow() { break; }
                }
            }
        }
    });
}

pub fn spawn_cache_worker(ctx: AppContext, mut shutdown_rx: watch::Receiver<bool>) {
    tokio::spawn(async move {
        // Wait a bit after startup
        tokio::time::sleep(tokio::time::Duration::from_secs(30)).await;

        let mut interval = tokio::time::interval(tokio::time::Duration::from_secs(3600)); // Every hour
        loop {
            tokio::select! {
                _ = interval.tick() => {
                    let cache = &ctx.core.http_cache;
                    // Prune to 512 MB
                    let _ = cache.prune(1024 * 1024 * 512).await;
                }
                _ = shutdown_rx.changed() => {
                    if *shutdown_rx.borrow() { break; }
                }
            }
        }
    });
}
