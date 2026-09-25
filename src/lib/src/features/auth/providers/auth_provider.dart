import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/app/init.dart' as app_init;
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/rust/app/context.dart';

/// `true` while an account session is open, `false` on the sign-in screen.
final FlutterSignal<AsyncState<bool>> authSignal = signal<AsyncState<bool>>(
  const AsyncLoading(),
);

/// Profile of the account whose session is open.
final FlutterSignal<UserAccountDto?> accountSignal = signal<UserAccountDto?>(
  null,
);

/// Session of the active account. Replaced on every account switch; anything
/// that captured the previous value must not write its results back.
final FlutterSignal<AppContext?> appContextSignal = signal<AppContext?>(null);

/// Every account signed in on this device, in the order they were added.
final FlutterSignal<List<StoredAccountDto>> accountsSignal =
    signal<List<StoredAccountDto>>(const []);

/// Uid of the account whose session is open.
final FlutterSignal<int?> activeAccountUidSignal = signal<int?>(null);

/// True while a session is being closed and another one opened.
final FlutterSignal<bool> sessionTransitionSignal = signal<bool>(false);

/// Stored entry of the active account (profile shown in the switcher).
final FlutterComputed<StoredAccountDto?> activeStoredAccountSignal = computed(
  () {
    final uid = activeAccountUidSignal();
    for (final a in accountsSignal()) {
      if (a.uid == uid) return a;
    }
    return null;
  },
  options: const ComputedOptions(name: 'activeStoredAccountSignal'),
);

Future<void> initAuth() => app_init.AppInit.initialize();

/// Signs in with an OAuth token. With a session already open the account is
/// added and switched to; the previous account stays signed in. Returns an
/// error message, or `null` on success.
Future<String?> login(String token) => app_init.AppInit.signIn(token);

/// Signs the active account out on this device (other accounts stay).
Future<void> logout() => app_init.AppInit.signOutActive();

Future<void> switchAccount(int uid) => app_init.AppInit.switchAccount(uid);

Future<void> removeAccount(int uid) => app_init.AppInit.removeAccount(uid);

/// Display name for an account: name, then login, then uid.
String accountDisplayName(StoredAccountDto a) {
  for (final v in [a.displayName, a.fullName, a.login]) {
    if (v != null && v.trim().isNotEmpty) return v.trim();
  }
  return 'Аккаунт ${a.uid}';
}
