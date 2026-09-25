import 'dart:async';

import 'package:youmuz/src/app/init.dart' as app_init;
import 'package:youmuz/src/features/auth/providers/auth_provider.dart';
import 'package:youmuz/src/features/core/providers/notification_provider.dart';
import 'package:youmuz/src/rust/app/context.dart';

/// Executes a Rust action safely, catches errors and shows a notification.
/// Returns true on success or if the action returned true, otherwise false.
///
/// The session is captured when the call starts. If the account changes
/// before it completes, the outcome belongs to the closed session and is
/// discarded (reported as `false`, errors are not shown).
Future<bool> runRustAction(
  Future<dynamic> Function(AppContext ctx) action,
) async {
  final ctx = appContextSignal.value;
  if (ctx == null) return false;
  try {
    final result = await action(ctx);
    if (!identical(appContextSignal.value, ctx)) return false;
    if (result is bool) return result;
    return true;
  } on Object catch (e) {
    if (identical(appContextSignal.value, ctx)) _handleRustError(e);
    return false;
  }
}

/// Safely fetches data from Rust.
/// Returns null if there is no context, on error, or when the account
/// changed while the request was in flight (so the data of one account can
/// never land in the state of another).
Future<T?> runRustFetch<T>(Future<T> Function(AppContext ctx) fetcher) async {
  final ctx = appContextSignal.value;
  if (ctx == null) return null;
  try {
    final result = await fetcher(ctx);
    if (!identical(appContextSignal.value, ctx)) return null;
    return result;
  } on Object catch (e) {
    if (identical(appContextSignal.value, ctx)) _handleRustError(e);
    return null;
  }
}

/// True for errors meaning the server no longer accepts the session token.
bool isUnauthorizedError(String message) =>
    message.contains('Invalid token or session expired') ||
    message.contains('Unauthorized') ||
    message.contains('session expired');

void _handleRustError(Object e) {
  final errorStr = e.toString();
  if (isUnauthorizedError(errorStr)) {
    unawaited(app_init.AppInit.handleSessionExpired());
  } else {
    showAppError(errorStr);
  }
}
