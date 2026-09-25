import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/app/init.dart' show AppInit;
import 'package:youmuz/src/features/auth/providers/auth_provider.dart';
import 'package:youmuz/src/features/core/providers/notification_provider.dart';
import 'package:youmuz/src/features/core/providers/visual_effects_provider.dart';
import 'package:youmuz/src/features/core/services/rust_bridge.dart';
import 'package:youmuz/src/features/library/providers/library_provider.dart';
import 'package:youmuz/src/rust/api/audio_fx.dart' as rust;
import 'package:youmuz/src/rust/api/library.dart' as rust;
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/rust/api/playback.dart' as rust;
import 'package:youmuz/src/rust/api/simple.dart' as rust;
import 'package:youmuz/src/rust/lib.dart';

// Player state signals
final FlutterSignal<PlaybackState?> playerStateSignal = signal<PlaybackState?>(
  null,
);
final FlutterSignal<PlaybackProgressDto?> playerProgressSignal =
    signal<PlaybackProgressDto?>(null);
final FlutterSignal<F32Array26> vibeTickSignal = signal<F32Array26>(
  F32Array26.init(),
);

final FlutterSignal<AudioQuality> audioQualitySignal = signal<AudioQuality>(
  AudioQuality.normal,
);

StreamSubscription<rust.AppEvent>? _eventSub;

Future<void> initPlayback() async {
  final ctx = appContextSignal.value;
  if (ctx == null) return;

  await _eventSub?.cancel();

  // Initialize app event stream
  _eventSub = rust.appEventStream(ctx: ctx).listen((event) {
    switch (event) {
      case rust.AppEvent_PlaybackStateChanged(field0: final state):
        playerStateSignal.value = state;
      case rust.AppEvent_PlaybackProgress(field0: final progress):
        playerProgressSignal.value = progress;
      case rust.AppEvent_VibeTick(field0: final tick):
        // Kept for consumers that opt in; the Graphite UI has no
        // audio-reactive background.
        if (vibeVisibleSignal.value) {
          vibeTickSignal.value = tick;
        }
      case rust.AppEvent_LikedTracksChanged(field0: final tracks):
        // Routed through the library provider so an active search filter is
        // respected; writing it verbatim replaced the user's search results
        // with the whole library whenever a like was toggled from the player.
        onLikedTracksChanged(tracks);
      case rust.AppEvent_AccountUpdated(field0: final account):
        accountSignal.value = account;
        unawaited(AppInit.refreshAccounts());
      case rust.AppEvent_Notification(field1: final message):
        showAppWarning(message);
      case rust.AppEvent_Error(field0: final message):
        if (isUnauthorizedError(message) || message.contains('401')) {
          unawaited(AppInit.handleSessionExpired());
        } else {
          showAppError(message);
        }
      case rust.AppEvent_TrackDownloadStarted(field0: final trackId):
        downloadingTracksSignal.value = {
          ...downloadingTracksSignal.value,
          trackId,
        };
      case rust.AppEvent_TrackDownloadFinished(field0: final trackId):
        downloadingTracksSignal.value = {
          ...downloadingTracksSignal.value,
        }..remove(trackId);
        unawaited(refreshDownloadedTracks());
      case rust.AppEvent_TrackDownloadFailed(
        field0: final trackId,
        field1: final error,
      ):
        downloadingTracksSignal.value = {
          ...downloadingTracksSignal.value,
        }..remove(trackId);
        showAppError('Ошибка загрузки трека: $error');
      case _:
        break;
    }
  });

  audioQualitySignal.value = await rust.getAudioQuality(ctx: ctx);

  _activateBufferingDelay();
  _activateLyricsOverlayReset();
  _activateWifiLock();
}

/// Cancel the event subscription and reset every playback signal.
///
/// Called on logout: the Rust `AppContext` (and with it the event stream) is
/// being torn down, so a late `PlaybackStateChanged` could otherwise
/// repopulate the player's state from the previous account.
void disposePlayback() {
  unawaited(_eventSub?.cancel());
  _eventSub = null;
  playerStateSignal.value = null;
  playerProgressSignal.value = null;
  vibeTickSignal.value = F32Array26.init();
  audioQualitySignal.value = AudioQuality.normal;
  // Cancel any in-flight volume flush so it cannot resurrect state after logout.
  _volumeFlushTimer?.cancel();
  _volumeFlushTimer = null;
  _pendingVolume = null;
  _lastVolumePush = null;
  _optimisticVolume.value = -1;
}

void _activateBufferingDelay() => _bufferingDelayEffect;
void _activateLyricsOverlayReset() => _lyricsOverlayResetEffect;
void _activateWifiLock() => _wifiLockEffect;

const _wifiLockChannel = MethodChannel('io.github.darkplayoff.youmuz/wifilock');

/// Prompts the user (once, via the system dialog) to exempt the app from
/// battery optimizations, so Android doesn't throttle/kill the background
/// audio engine independently of the wake lock held during playback.
Future<void> requestIgnoreBatteryOptimizations() async {
  if (!Platform.isAndroid) return;
  await _wifiLockChannel
      .invokeMethod('requestIgnoreBatteryOptimizations')
      .catchError((_) {});
}

final EffectCleanup _wifiLockEffect = effect(() {
  if (!Platform.isAndroid) return;

  final state = playerStateSignal();
  final shouldHold =
      (state?.isBuffering ?? false) || (state?.isPlaying ?? false);

  if (shouldHold) {
    unawaited(_wifiLockChannel.invokeMethod('acquire').catchError((e) {}));
  } else {
    unawaited(_wifiLockChannel.invokeMethod('release').catchError((e) {}));
  }
});

// Signal for current track ID only
final FlutterComputed<String?> currentTrackIdSignal = computed(
  () => playerStateSignal.value?.currentTrack?.id,
  options: const ComputedOptions(name: 'currentTrackIdSignal'),
);

/// Volume shown by the UI while the user is dragging the slider.
///
/// Rust echoes the value back, but only on the throttled push, so without this
/// the thumb would lag the pointer by up to a full throttle window.
final FlutterSignal<int> _optimisticVolume = signal(-1);

// Signal for volume only
final FlutterComputed<int> playerVolumeSignal = computed(
  () {
    final optimistic = _optimisticVolume.value;
    if (optimistic >= 0) return optimistic;
    return playerStateSignal.value?.volume ?? 100;
  },
  options: const ComputedOptions(name: 'playerVolumeSignal'),
);

// Signal for playback status only
final FlutterComputed<bool> isPlayingSignal = computed(
  () => playerStateSignal.value?.isPlaying ?? false,
  options: const ComputedOptions(name: 'isPlayingSignal'),
);

// Shuffle signal
final FlutterComputed<bool> isShuffledSignal = computed(
  () => playerStateSignal.value?.isShuffled ?? false,
  options: const ComputedOptions(name: 'isShuffledSignal'),
);

// Repeat mode signal
final FlutterComputed<RepeatModeDto> repeatModeSignal = computed(
  () => playerStateSignal.value?.repeatMode ?? RepeatModeDto.none,
  options: const ComputedOptions(name: 'repeatModeSignal'),
);

// Signals for liking/disliking the current track
final FlutterComputed<bool> isLikedSignal = computed(
  () => playerStateSignal.value?.currentTrack?.isLiked ?? false,
  options: const ComputedOptions(name: 'isLikedSignal'),
);

final FlutterComputed<bool> isDislikedSignal = computed(
  () => playerStateSignal.value?.currentTrack?.isDisliked ?? false,
  options: const ComputedOptions(name: 'isDislikedSignal'),
);

// Signal for current wave seeds
final FlutterComputed<List<String>> currentWaveSeedsSignal = computed(
  () => playerStateSignal.value?.currentWaveSeeds ?? [],
  options: const ComputedOptions(name: 'currentWaveSeedsSignal'),
);

// Track metadata (static data only)
final FlutterComputed<
  ({
    String? id,
    String title,
    String? version,
    List<TrackArtistDto> artists,
    String? coverUrl,
    String? albumId,
    String? codec,
  })
>
trackMetadataSignal = computed(() {
  final state = playerStateSignal.value;
  return (
    id: state?.currentTrack?.id,
    title: state?.currentTrack?.title ?? 'Тишина',
    version: state?.currentTrack?.version,
    artists: state?.currentTrack?.artists ?? [],
    coverUrl: state?.currentTrack?.coverUrl,
    albumId: state?.currentTrack?.albumId,
    codec: state?.codec,
  );
}, options: const ComputedOptions(name: 'trackMetadataSignal'));

// Track progress (updates frequently)
final FlutterComputed<({double durationMs, double positionMs})>
trackProgressSignal = computed(() {
  final progress = playerProgressSignal.value;
  return (
    durationMs: (progress?.durationMs ?? 1).toDouble(),
    positionMs: (progress?.positionMs ?? 0).toDouble(),
  );
}, options: const ComputedOptions(name: 'trackProgressSignal'));

// Signal for audio output devices
final FlutterSignal<List<String>> audioDevicesSignal = signal<List<String>>([]);
final FlutterSignal<String?> selectedAudioDeviceSignal = signal<String?>(null);

Future<void> refreshAudioDevices() async {
  final ctx = appContextSignal.value;
  if (ctx == null) return;
  audioDevicesSignal.value = await rust.getAudioDevices(ctx: ctx);
}

Future<void> setAudioDevice(String deviceName) async {
  final ctx = appContextSignal.value;
  if (ctx == null) return;
  selectedAudioDeviceSignal.value = deviceName.isEmpty ? null : deviceName;
  await rust.setAudioDevice(ctx: ctx, deviceName: deviceName);
}

// Signal for cover URL only to avoid re-calculating on pause/likes
final FlutterComputed<String?> currentCoverUrlSignal = computed(
  () => playerStateSignal.value?.currentTrack?.coverUrl,
);

// Signal for local cover URI from Rust cache
final FutureSignal<Uri?> localCoverUriSignal = computedAsync(() async {
  final url = currentCoverUrlSignal();
  final ctx = appContextSignal.value;
  if (url == null || ctx == null) return null;

  final path = await rust.getCachedImagePath(ctx: ctx, url: url);
  if (path != null) return Uri.file(path);
  return Uri.parse(url); // Fallback to remote if not yet cached
}, options: const AsyncSignalOptions(name: 'localCoverUriSignal'));

// Signal for queue tracks
final FutureSignal<List<SimpleTrackDto>> queueTracksSignal = computedAsync(
  () async {
    final ctx = appContextSignal();
    // Depend on the narrow revision key, NOT on `playerStateSignal` itself.
    // `FutureSignal` has no value-equality gate, so depending on the whole
    // state object re-ran `getQueue()` on every write — including the ones a
    // volume-slider drag produces at pointer rate.
    final _ = queueRevisionSignal();
    // Read the rest untracked: it must not add dependencies.
    final state = playerStateSignal.peek();
    if (ctx == null || state == null) return const [];

    return await rust.getQueue(ctx: ctx);
  },
  options: const AsyncSignalOptions(name: 'queueTracksSignal'),
);

// Signal for previous track in queue
final FlutterComputed<SimpleTrackDto?> previousTrackSignal = computed(() {
  final state = playerStateSignal.value;
  final queue = queueTracksSignal().value ?? const [];
  if (state == null || queue.isEmpty) return null;

  final index = state.queueIndex;
  final repeatMode = state.repeatMode;

  if (index > 0 && index < queue.length) {
    return queue[index - 1];
  } else if (index == 0 && repeatMode == RepeatModeDto.all) {
    return queue.last;
  }
  return null;
}, options: const ComputedOptions(name: 'previousTrackSignal'));

// Signal for next track in queue
final FlutterComputed<SimpleTrackDto?> nextTrackSignal = computed(() {
  final state = playerStateSignal.value;
  final queue = queueTracksSignal().value ?? const [];
  if (state == null || queue.isEmpty) return null;

  final index = state.queueIndex;
  final repeatMode = state.repeatMode;

  if (index + 1 < queue.length) {
    return queue[index + 1];
  } else if (index + 1 == queue.length && repeatMode == RepeatModeDto.all) {
    return queue.first;
  }
  return null;
}, options: const ComputedOptions(name: 'nextTrackSignal'));

// Buffering indicator that only shows once the track has been stalled > 3s,
// to avoid flickering on short buffering hiccups.
Timer? _bufferingDelayTimer;
final FlutterSignal<bool> showBufferingIndicatorSignal = signal(false);
final EffectCleanup _bufferingDelayEffect = effect(() {
  final state = playerStateSignal();
  final stalled = state != null && !state.isPlaying && state.isBuffering;

  if (!stalled) {
    _bufferingDelayTimer?.cancel();
    _bufferingDelayTimer = null;
    showBufferingIndicatorSignal.value = false;
    return;
  }

  _bufferingDelayTimer ??= Timer(const Duration(seconds: 3), () {
    _bufferingDelayTimer = null;
    showBufferingIndicatorSignal.value = true;
  });
});

// Windows taskbar thumbnail toolbar is handled natively in Rust
// (src/rust/src/audio/taskbar.rs): button state is derived from audio signals
// there, and WM_COMMAND actions go straight to the audio actor / library
// logic without crossing the FFI boundary.

// Track position from progress
final FlutterComputed<double> playerPositionMsSignal = computed(
  () => (playerProgressSignal.value?.positionMs ?? 0).toDouble(),
  options: const ComputedOptions(name: 'playerPositionMsSignal'),
);

final FlutterSignal<bool> showLyricsSignal = signal<bool>(false);
final FlutterSignal<bool> hideLyricsOverlaySignal = signal<bool>(false);

/// True while the lyrics text for the currently displayed track is still
/// being fetched, or once fetched turns out empty. Used to keep the
/// background scrim off in both cases — dimming only comes back once
/// actual lyrics lines have loaded.
final FlutterSignal<bool> lyricsSuppressDimSignal = signal<bool>(false);

/// A key derived from the fields of `PlaybackState` that the queue actually
/// depends on.
///
/// `queueTracksSignal` used to read `playerStateSignal()` wholesale, which
/// meant *every* state write invalidated it — and a `FutureSignal` has no
/// value-equality gate, so each invalidation re-ran `rust.getQueue()` and
/// deserialised the entire queue into fresh Dart objects. Dragging the volume
/// slider fires state writes at pointer rate, so that was a full-queue
/// FFI round trip 60 times a second. Depending on this key instead makes the
/// refetch happen only when the queue actually changed.
final FlutterComputed<int> queueRevisionSignal = computed(
  () {
    final s = playerStateSignal.peek();
    if (s == null) return 0;
    return Object.hash(s.queueCount, s.isShuffled, s.queueIndex);
  },
  options: const ComputedOptions(name: 'queueRevisionSignal'),
);

/// Coalesce volume writes.
///
/// The slider's `onChanged` fires on every pointer frame; each call was an FFI
/// round trip *plus* a spawned SQLite write of the `volume` setting, so a
/// single drag produced ~60 of each. Push at most every [VOLUME_PUSH_INTERVAL]
/// and make sure the final value is always delivered.
const Duration _volumePushInterval = Duration(milliseconds: 50);
DateTime? _lastVolumePush;
Timer? _volumeFlushTimer;
int? _pendingVolume;

// Reset overlay visibility on track change
final EffectCleanup _lyricsOverlayResetEffect = effect(() {
  currentTrackIdSignal(); // Just call to track dependency
  hideLyricsOverlaySignal.value = false;
  lyricsSuppressDimSignal.value = false;
});

final FlutterSignal<EqualizerDto?> equalizerSignal = signal<EqualizerDto?>(
  null,
);
final FlutterSignal<List<AudioEffectDto>> audioEffectsSignal =
    signal<List<AudioEffectDto>>([]);

Future<void> refreshEqualizer() async {
  final ctx = appContextSignal.value;
  if (ctx == null) return;
  equalizerSignal.value = await rust.getEqualizer(ctx: ctx);
}

Future<void> refreshAudioEffects() async {
  final ctx = appContextSignal.value;
  if (ctx == null) return;
  audioEffectsSignal.value = await rust.getAudioEffects(ctx: ctx);
}

// Global playback control methods
class PlaybackController {
  static Future<void> playTrack(String trackId) =>
      runRustAction((ctx) => rust.playTrack(ctx: ctx, trackId: trackId));
  static Future<void> playLikedTrack(String trackId) =>
      runRustAction((ctx) => rust.playLikedTrack(ctx: ctx, trackId: trackId));
  static Future<void> playAlbumTrack(int albumId, String trackId) =>
      runRustAction(
        (ctx) =>
            rust.playAlbumTrack(ctx: ctx, albumId: albumId, trackId: trackId),
      );
  static Future<void> playPlaylistTrack(String uid, int kind, String trackId) =>
      runRustAction(
        (ctx) => rust.playPlaylistTrack(
          ctx: ctx,
          uid: uid,
          kind: kind,
          trackId: trackId,
        ),
      );
  static Future<void> playPlaylist(String uid, int kind) =>
      runRustAction((ctx) => rust.playPlaylist(ctx: ctx, uid: uid, kind: kind));
  static Future<void> playAlbum(int albumId) =>
      runRustAction((ctx) => rust.playAlbum(ctx: ctx, albumId: albumId));
  static Future<void> togglePlay() =>
      runRustAction((ctx) => rust.togglePlayPause(ctx: ctx));

  static Future<void> play() => runRustAction((ctx) => rust.play(ctx: ctx));

  static Future<void> pause() => runRustAction((ctx) => rust.pause(ctx: ctx));
  static Future<void> next() => runRustAction((ctx) => rust.playNext(ctx: ctx));
  static Future<void> prev() => runRustAction((ctx) => rust.playPrev(ctx: ctx));
  static Future<void> toggleShuffle() =>
      runRustAction((ctx) => rust.toggleShuffle(ctx: ctx));
  static Future<void> toggleRepeat() =>
      runRustAction((ctx) => rust.toggleRepeatMode(ctx: ctx));
  static Future<void> stop() => runRustAction((ctx) => rust.stop(ctx: ctx));
  static Future<void> toggleLike({required String trackId}) =>
      runRustAction((ctx) => rust.toggleLike(ctx: ctx, trackId: trackId));
  static Future<void> toggleDislike({required String trackId}) =>
      runRustAction((ctx) => rust.toggleDislike(ctx: ctx, trackId: trackId));

  static Future<void> startTrackWave(String trackId, [String? title]) =>
      runRustAction(
        (ctx) => rust.startWave(
          ctx: ctx,
          seeds: [
            if (title != null) 'track:$trackId:$title' else 'track:$trackId',
          ],
        ),
      );

  /// Rotor station built around one artist.
  static Future<void> startArtistWave(String artistId) => runRustAction(
    (ctx) => rust.startWave(ctx: ctx, seeds: ['artist:$artistId']),
  );
  /// Throttled volume push.
  ///
  /// The slider's `onChanged` fires per pointer frame; each call was an FFI
  /// round trip *and* a spawned SQLite write of the `volume` setting, so one
  /// drag produced ~60 of each. Push at most every 50ms, and always deliver
  /// the final value so the drag never ends on a stale volume.
  static Future<void> changeVolume(int volume) {
    // Update the local (optimistic) signal immediately so the slider feels
    // instant, but only push to Rust on a timer: `setVolume` also persists the
    // setting to SQLite, so a 60Hz drag meant ~60 DB writes/sec plus a full
    // FFI round trip each.
    _pendingVolume = volume;
    _optimisticVolume.value = volume;

    final now = DateTime.now();
    final last = _lastVolumePush;
    if (last == null || now.difference(last) >= _volumePushInterval) {
      return _flushVolume();
    }

    // Inside the window: make sure a flush is scheduled. The final value is
    // always delivered, so the drag never ends on a stale volume.
    _volumeFlushTimer ??= Timer(_volumePushInterval, () {
      unawaited(_flushVolume());
    });
    return Future<void>.value();
  }

  static Future<void> _flushVolume() {
    _volumeFlushTimer?.cancel();
    _volumeFlushTimer = null;
    final volume = _pendingVolume;
    if (volume == null) return Future<void>.value();
    _lastVolumePush = DateTime.now();
    return runRustAction((ctx) async {
      await rust.setVolume(ctx: ctx, volume: volume);
      // Rust has caught up; drop the optimistic override so the authoritative
      // value takes over again.
      if (_pendingVolume == volume) {
        _pendingVolume = null;
        _optimisticVolume.value = -1;
      }
    });
  }

  /// Force any throttled volume change out immediately (e.g. on drag end).
  static Future<void> commitVolume() => _flushVolume();

  static Future<void> changeTransientVolumeGain(int gain) => runRustAction(
    (ctx) => rust.setTransientVolumeGain(ctx: ctx, gain: gain),
  );
  static Future<void> seekTo(Duration duration) => runRustAction(
    (ctx) => rust.seek(ctx: ctx, positionMs: duration.inMilliseconds),
  );

  static Future<void> setQuality(AudioQuality quality) =>
      runRustAction((ctx) async {
        await rust.setAudioQuality(ctx: ctx, quality: quality);
        audioQualitySignal.value = quality;
      });

  static Future<void> setEqualizerEnabled({required bool enabled}) =>
      runRustAction((ctx) async {
        await rust.setEqualizerEnabled(ctx: ctx, enabled: enabled);
        await refreshEqualizer();
      });

  static Future<void> setEqualizerBand(int index, double gainDb) =>
      runRustAction((ctx) async {
        await rust.setEqualizerBand(ctx: ctx, index: index, gainDb: gainDb);
        // Local update for smoothness
        final current = equalizerSignal.value;
        if (current != null) {
          final newBands = List<BandDto>.from(current.bands);
          newBands[index] = BandDto(
            frequency: current.bands[index].frequency,
            gainDb: gainDb,
            index: index,
          );
          equalizerSignal.value = EqualizerDto(
            enabled: current.enabled,
            bands: newBands,
          );
        }
      });

  static Future<void> resetEqualizer() => runRustAction((ctx) async {
    final current = equalizerSignal.value;
    if (current != null) {
      for (var i = 0; i < current.bands.length; i++) {
        await rust.setEqualizerBand(ctx: ctx, index: i, gainDb: 0);
      }
      await refreshEqualizer();
    }
  });

  static Future<void> setEffectEnabled(String id, {required bool enabled}) =>
      runRustAction((ctx) async {
        await rust.setEffectEnabled(ctx: ctx, id: id, enabled: enabled);
        await refreshAudioEffects();
      });

  static Future<void> setEffectParam(String id, int index, double value) =>
      runRustAction((ctx) async {
        await rust.setEffectParam(ctx: ctx, id: id, index: index, value: value);
        // Local update for smoothness
        final currentEffects = List<AudioEffectDto>.from(
          audioEffectsSignal.value,
        );
        final effectIndex = currentEffects.indexWhere((e) => e.id == id);
        if (effectIndex != -1) {
          final effect = currentEffects[effectIndex];
          final newParams = List<EffectParamDto>.from(effect.params);
          final param = newParams[index];
          newParams[index] = EffectParamDto(
            name: param.name,
            value: value,
            defaultValue: param.defaultValue,
            min: param.min,
            max: param.max,
            step: param.step,
            unit: param.unit,
            index: index,
          );
          currentEffects[effectIndex] = AudioEffectDto(
            id: effect.id,
            name: effect.name,
            enabled: effect.enabled,
            params: newParams,
          );
          audioEffectsSignal.value = currentEffects;
        }
      });

  static Future<void> resetEffect(String id) => runRustAction((ctx) async {
    await rust.resetEffect(ctx: ctx, id: id);
    await refreshAudioEffects();
  });
}
