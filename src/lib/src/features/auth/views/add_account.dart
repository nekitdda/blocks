import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/features/auth/views/auth/auth_screens.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Opens the sign-in screen over the app to add (or re-authorize) an account.
/// The current session keeps running until the new account signs in, then
/// the app switches to it.
Future<void> showAddAccountFlow(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: GDurations.medium,
      reverseTransitionDuration: GDurations.fast,
      pageBuilder: (context, _, _) => const LoginScreen(addingAccount: true),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: GCurves.emphasized);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}
