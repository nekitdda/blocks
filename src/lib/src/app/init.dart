import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/auth/providers/auth_provider.dart';
import 'package:youmuz/src/features/core/providers/navigation_provider.dart';
import 'package:youmuz/src/features/core/providers/notification_provider.dart';
import 'package:youmuz/src/features/core/providers/visual_effects_provider.dart';
import 'package:youmuz/src/features/library/providers/library_provider.dart'
    show clearLibraryState, initLibrary;
import 'package:youmuz/src/features/playback/providers/audio_focus_manager.dart';
import 'package:youmuz/src/features/playback/providers/audio_handler.dart';
import 'package:youmuz/src/features/playback/providers/lyrics_provider.dart'
    show clearLyricsCache;
import 'package:youmuz/src/features/playback/providers/playback_provider.dart'
    show disposePlayback, initPlayback, requestIgnoreBatteryOptimizations;
import 'package:youmuz/src/features/search/providers/search_provider.dart'
    show clearSearchState;
import 'package:youmuz/src/rust/api/auth.dart' as rust;
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/rust/api/playback.dart' as rust_playback;
import 'package:youmuz/src/rust/api/simple.dart' as simple;
import 'package:youmuz/src/rust/app/context.dart';
import 'package:youmuz/src/rust/frb_generated.dart';

export 'package:youmuz/src/features/auth/providers/auth_provider.dart'
    show initAuth, login, logout;

/// Application start-up and the account-session lifecycle.
///
/// Exactly one account has an open session at a time. Switching closes it in
/// Rust (audio released, position stored) and resets every account-bound
/// signal before the next session attaches, so no state crosses accounts.
class AppInit {
  static bool _handlingExpiry = false;

  static Future<void> initialize() async {
    SignalsObserver.instance = null;

    await RustLib.init();

    if (Platform.isAndroid) {
      await _initAudioService();
    }

    final appDir = await _resolveDataDir();
    await simple.initAppInfrastructure(basePath: appDir.path);

    try {
      final settings = await simple.getInitialSettings();
      autoHideNavbarSignal.value = settings.autoHideNavbar;
      closeToTraySignal.value = settings.closeToTray;
      customTitlebarSignal.value = settings.customTitlebar;
      vibeVisibleSignal.value = settings.vibeAnimationEnabled;
      vibeRenderScaleSignal.value = settings.vibeRenderScale;
      blurEffectsEnabledSignal.value = settings.blurEffectsEnabled;
    } on Object catch (_) {}

    unawaited(_restoreSessionOnLaunch());
  }

  /// Rust backend storage (yamusic_v2.db, accounts/, http cache) lives in the
  /// platform application-support directory, not Documents. One-time move
  /// for installs predating this: the auth token is stored inside the DB,
  /// so moving without migration would log every user out and orphan
  /// downloaded tracks.
  static Future<Directory> _resolveDataDir() async {
    final support = await getApplicationSupportDirectory();
    await _migrateLegacyDataDir(support);
    return support;
  }

  static Future<void> _migrateLegacyDataDir(Directory support) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      if (docs.path == support.path) return;
      final legacyDb = File(
        '${docs.path}${Platform.pathSeparator}yamusic_v2.db',
      );
      if (!await legacyDb.exists()) return;
      final targetDb = File(
        '${support.path}${Platform.pathSeparator}yamusic_v2.db',
      );
      if (targetDb.existsSync()) return;
      await support.create(recursive: true);
      for (final name in [
        'yamusic_v2.db',
        'yamusic_v2.db-wal',
        'yamusic_v2.db-shm',
        'http_cache',
        'offline_tracks',
      ]) {
        await _moveEntity(docs.path, support.path, name);
      }
    } on Object {
      // Migration is best-effort only; worst case the app starts fresh.
    }
  }

  static Future<void> _moveEntity(
    String fromDir,
    String toDir,
    String name,
  ) async {
    try {
      final srcDir = Directory('$fromDir${Platform.pathSeparator}$name');
      if (await srcDir.exists()) {
        await srcDir.rename('$toDir${Platform.pathSeparator}$name');
        return;
      }
      final srcFile = File('$fromDir${Platform.pathSeparator}$name');
      if (await srcFile.exists()) {
        await srcFile.rename('$toDir${Platform.pathSeparator}$name');
      }
    } on Object {
      // Best-effort per entry.
    }
  }

  static Future<void> _initAudioService() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    await AudioFocusManager.initialize(session);

    await AudioService.init(
      builder: YouMuzAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'io.github.darkplayoff.youmuz.playback',
        androidNotificationChannelName: 'YouMuz Playback',
        androidNotificationOngoing: true,
        androidShowNotificationBadge: true,
        androidNotificationIcon: 'drawable/ic_notification',
      ),
    );

    unawaited(requestIgnoreBatteryOptimizations());
  }

  static Future<void> _restoreSessionOnLaunch() async {
    final context = await rust.tryAutoLogin();
    await refreshAccounts();
    if (context == null) {
      authSignal.value = const AsyncData(false);
      return;
    }
    await _attachSession(context);
    authSignal.value = const AsyncData(true);
  }

  static Future<void> refreshAccounts() async {
    try {
      accountsSignal.value = await rust.listAccounts();
    } on Object catch (e) {
      debugPrint('Failed to list accounts: $e');
    }
  }

  /// Connects a freshly opened session to the UI.
  static Future<void> _attachSession(AppContext context) async {
    appContextSignal.value = context;
    activeAccountUidSignal.value = rust.sessionAccountUid(ctx: context);

    // Event stream and playback signals first, so the restored track shows up.
    await initPlayback();

    unawaited(_loadAccountInfo(context));
    unawaited(initLibrary());
    unawaited(_restorePlayback(context));
  }

  /// Resets every account-bound signal, then closes the session in Rust.
  static Future<void> _detachSession() async {
    final context = appContextSignal.value;
    // Stop listening first: late events of the closing session are dropped.
    disposePlayback();
    clearLibraryState();
    // Lyrics sources are a per-account preference.
    clearLyricsCache();
    clearSearchState();
    resetNavigation();
    accountSignal.value = null;
    appContextSignal.value = null;
    activeAccountUidSignal.value = null;
    if (context != null) {
      await rust.closeSession(ctx: context);
    }
  }

  static Future<void> _loadAccountInfo(AppContext context) async {
    try {
      final account = await rust.getAccountInfo(ctx: context);
      if (!identical(appContextSignal.value, context)) return;
      accountSignal.value = account;
      // The switcher entry was refreshed from the same profile.
      unawaited(refreshAccounts());
    } on Object {
      if (identical(appContextSignal.value, context)) {
        accountSignal.value = null;
      }
    }
  }

  /// Puts the account's last track back into the player, paused.
  static Future<void> _restorePlayback(AppContext context) async {
    try {
      final state = await rust.restoreSavedState(ctx: context);
      if (state == null || !identical(appContextSignal.value, context)) return;
      await rust_playback.restoreAndPlay(
        ctx: context,
        trackId: state.trackId,
        positionMs: state.positionMs,
        isPlaying: false,
      );
    } on Object catch (e) {
      debugPrint('Failed to restore playback: $e');
    }
  }

  /// Closes the current session (if any) and opens [uid]'s.
  static Future<void> _openSession(int uid) async {
    if (appContextSignal.value != null) {
      await _detachSession();
    }
    final context = await rust.openAccountSession(uid: uid);
    await _attachSession(context);
    authSignal.value = const AsyncData(true);
  }

  static StoredAccountDto? _mostRecentUsable({int? excluding}) {
    StoredAccountDto? best;
    for (final a in accountsSignal.value) {
      if (a.needsLogin || a.uid == excluding) continue;
      if (best == null || a.lastActiveAt > best.lastActiveAt) best = a;
    }
    return best;
  }

  /// Opens the most recently used remaining account, or the sign-in screen.
  static Future<void> _openFallback({int? excluding}) async {
    final next = _mostRecentUsable(excluding: excluding);
    if (next == null) {
      authSignal.value = const AsyncData(false);
      return;
    }
    try {
      await _openSession(next.uid);
    } on Object catch (e) {
      showAppError('Не удалось открыть аккаунт: $e');
      authSignal.value = const AsyncData(false);
    }
  }

  /// Result of the sign-in screen. Adds the account (keeping the current one
  /// signed in) and switches to it. Returns an error message on failure.
  static Future<String?> signIn(String token) async {
    if (sessionTransitionSignal.value) return 'Подождите, аккаунт переключается';
    sessionTransitionSignal.value = true;
    try {
      final StoredAccountDto account;
      try {
        account = await rust.addAccount(token: token);
      } on Object catch (e) {
        return _describeSignInError(e);
      }
      await refreshAccounts();
      if (account.uid == activeAccountUidSignal.value) {
        // Signed in to the account that is already open: token refreshed.
        return null;
      }
      final previous = activeAccountUidSignal.value;
      try {
        await _openSession(account.uid);
      } on Object catch (e) {
        if (previous != null) {
          await _openFallback();
        } else {
          authSignal.value = const AsyncData(false);
        }
        return 'Не удалось открыть аккаунт: $e';
      }
      return null;
    } finally {
      sessionTransitionSignal.value = false;
      unawaited(refreshAccounts());
    }
  }

  static String _describeSignInError(Object e) {
    final text = e.toString();
    final lower = text.toLowerCase();
    if (lower.contains('invalidtoken') || lower.contains('invalid token') || lower.contains('unauthorized')) {
      return 'Токен недействителен. Войдите заново.';
    }
    if (lower.contains('network') || lower.contains('timeout') || lower.contains('connection')) {
      return 'Нет подключения к сети.';
    }
    return 'Не удалось войти: $text';
  }

  static Future<void> switchAccount(int uid) async {
    if (sessionTransitionSignal.value) return;
    if (uid == activeAccountUidSignal.value) return;
    final previous = activeAccountUidSignal.value;
    sessionTransitionSignal.value = true;
    try {
      try {
        await _openSession(uid);
      } on Object catch (e) {
        showAppError('Не удалось переключить аккаунт: $e');
        if (previous != null && previous != uid) {
          try {
            await _openSession(previous);
          } on Object {
            await _openFallback(excluding: uid);
          }
        } else {
          await _openFallback(excluding: uid);
        }
      }
    } finally {
      sessionTransitionSignal.value = false;
      unawaited(refreshAccounts());
    }
  }

  /// Signs [uid] out on this device and deletes its local data. Removing the
  /// active account opens the most recently used remaining one.
  static Future<void> removeAccount(int uid) async {
    if (sessionTransitionSignal.value) return;
    final isActive = uid == activeAccountUidSignal.value;
    sessionTransitionSignal.value = true;
    try {
      if (isActive) {
        await _detachSession();
      }
      try {
        await rust.removeAccount(uid: uid);
      } on Object catch (e) {
        showAppError('Не удалось удалить аккаунт: $e');
      }
      await refreshAccounts();
      if (isActive) {
        await _openFallback(excluding: uid);
      }
    } finally {
      sessionTransitionSignal.value = false;
    }
  }

  static Future<void> signOutActive() async {
    final uid = activeAccountUidSignal.value;
    if (uid != null) await removeAccount(uid);
  }

  /// The server rejected the active session's token: keep the account listed
  /// (marked "sign in again") and move on to another account.
  static Future<void> handleSessionExpired() async {
    if (_handlingExpiry || sessionTransitionSignal.value) return;
    final uid = activeAccountUidSignal.value;
    if (uid == null) return;
    _handlingExpiry = true;
    sessionTransitionSignal.value = true;
    try {
      showAppError('Сессия аккаунта истекла. Войдите снова.');
      await _detachSession();
      try {
        await rust.markAccountNeedsLogin(uid: uid);
      } on Object catch (e) {
        debugPrint('Failed to mark account: $e');
      }
      await refreshAccounts();
      await _openFallback(excluding: uid);
    } finally {
      sessionTransitionSignal.value = false;
      _handlingExpiry = false;
    }
  }
}
