import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:webview_all/webview_all.dart';
import 'package:window_manager/window_manager.dart';
import 'package:youmuz/src/features/auth/providers/auth_provider.dart';
import 'package:youmuz/src/features/auth/views/auth/login_dialogs.dart';
import 'package:youmuz/src/features/core/providers/navigation_provider.dart';
import 'package:youmuz/src/features/core/views/layout.dart';
import 'package:youmuz/src/features/core/views/layout/header.dart';
import 'package:youmuz/src/features/settings/services/update_service.dart';
import 'package:youmuz/src/features/settings/views/update_dialog.dart';
import 'package:youmuz/src/rust/api/simple.dart' as simple;
import 'package:youmuz/src/ui/ui.dart';

export 'package:youmuz/src/features/auth/views/auth/login_dialogs.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  bool _updateChecked = false;

  void _checkForUpdatesOnce() {
    if (_updateChecked) return;
    _updateChecked = true;
    unawaited(() async {
      try {
        final ctx = appContextSignal.value;
        if (ctx == null) return;
        if (!await simple.isUpdateCheckEnabled(ctx: ctx)) return;
        final info = await UpdateService.checkForUpdates();
        if (info != null && info.hasUpdate && mounted) {
          UpdateDialog.show(context, initialInfo: info);
        }
      } on Object catch (e) {
        debugPrint('Error checking for updates: $e');
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final authState = authSignal();
        return authState.map(
          data: (isLoggedIn) {
            if (isLoggedIn) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdatesOnce());
              return const AppLayout();
            }
            return const LoginScreen();
          },
          error: (Object e, _) => LoginScreen(initialError: '$e'),
          loading: () => const _Splash(),
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: GColors.background,
      body: Center(child: GraphiteLogo(showLabel: false)),
    );
  }
}

/// Extracts the OAuth token from a pasted token or redirect URL.
String? parseTokenInput(String input) {
  var token = input.trim();
  try {
    token = Uri.decodeFull(token);
  } on Object catch (_) {}
  token = token.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u00A0]'), '');
  token = token.replaceAll(RegExp(r'[^\x21-\x7E]'), '');
  final urlMatch = RegExp('access_token=([^&/#?]+)').firstMatch(token);
  if (urlMatch != null) {
    token = urlMatch.group(1)!;
  } else {
    final directMatch = RegExp('(y0_[a-zA-Z0-9._-]+)').firstMatch(token);
    if (directMatch != null) token = directMatch.group(1)!;
  }
  if (token.isEmpty || token.startsWith('http')) return null;
  return token;
}

/// Sign-in screen. With [addingAccount] it is shown over the running app to
/// add another account; the current one stays signed in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.addingAccount = false, this.initialError});

  final bool addingAccount;
  final String? initialError;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _tokenController = TextEditingController();
  bool _busy = false;
  late String? _error = widget.initialError;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _submit(String? token) async {
    if (token == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await login(token);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null && widget.addingAccount) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _webLogin() async {
    if (widget.addingAccount) {
      // The embedded browser still holds the current account's Yandex
      // session; without this Yandex would authorize that account again.
      await WebViewCookieManager().clearCookies();
    }
    if (!mounted) return;
    final String? token;
    if (Platform.isAndroid) {
      token = await Navigator.push<String>(
        context,
        MaterialPageRoute<String>(
          fullscreenDialog: true,
          builder: (_) => const YandexLoginDialog(fullscreen: true),
        ),
      );
    } else {
      token = await showGDialog<String>(context, builder: (_) => const YandexLoginDialog());
    }
    await _submit(token);
  }

  Future<void> _deviceLogin() async {
    final String? token;
    if (Platform.isAndroid) {
      token = await Navigator.push<String>(
        context,
        MaterialPageRoute<String>(
          fullscreenDialog: true,
          builder: (_) => const YandexDeviceLoginDialog(fullscreen: true),
        ),
      );
    } else {
      token = await showGDialog<String>(context, builder: (_) => const YandexDeviceLoginDialog());
    }
    await _submit(token);
  }

  void _submitField() {
    final token = parseTokenInput(_tokenController.text);
    if (token == null) {
      setState(() => _error = 'Вставьте токен y0_… или ссылку с access_token.');
      return;
    }
    unawaited(_submit(token));
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    // Embedded WebView is unreliable on Linux: offer the code flow first.
    final codeFirst = Platform.isLinux;
    final webButton = GButton(
      label: 'Войти через Яндекс',
      icon: LucideIcons.globe,
      size: GButtonSize.lg,
      expand: true,
      variant: codeFirst ? GButtonVariant.secondary : GButtonVariant.primary,
      onPressed: _busy ? null : () => unawaited(_webLogin()),
    );
    final codeButton = GButton(
      label: 'Войти по коду устройства',
      icon: LucideIcons.monitor,
      size: GButtonSize.lg,
      expand: true,
      variant: codeFirst ? GButtonVariant.primary : GButtonVariant.secondary,
      onPressed: _busy ? null : () => unawaited(_deviceLogin()),
    );

    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(alignment: Alignment.centerLeft, child: GraphiteLogo()),
          const SizedBox(height: 40),
          Text(
            widget.addingAccount ? 'Добавить аккаунт' : 'Вход в YouMuz',
            style: GText.headline(36),
          ),
          const SizedBox(height: 12),
          Text(
            widget.addingAccount
                ? 'Войдите в другой аккаунт Яндекса. Текущий останется в списке — переключаться можно через аватар в шапке.'
                : 'Альтернативный клиент Яндекс Музыки. Войдите в аккаунт Яндекса — позже можно добавить ещё несколько.',
            style: GText.sm(color: GColors.mutedForeground).copyWith(height: 1.6),
          ),
          const SizedBox(height: 32),
          if (codeFirst) ...[codeButton, const SizedBox(height: 8), webButton] else ...[
            webButton,
            const SizedBox(height: 8),
            codeButton,
          ],
          const SizedBox(height: 28),
          Row(
            children: [
              const Expanded(child: GDivider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('или вставьте токен', style: GText.xs(color: GColors.mutedForeground)),
              ),
              const Expanded(child: GDivider()),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _tokenController,
            enabled: !_busy,
            style: GText.sm(),
            onSubmitted: (_) => _submitField(),
            decoration: InputDecoration(
              hintText: 'y0_… или ссылка с access_token',
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: GColors.brand),
                        ),
                      )
                    : GIconButton(
                        icon: LucideIcons.arrowRight,
                        tooltip: 'Войти',
                        onPressed: _submitField,
                      ),
              ),
              suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 36),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: GDurations.fast,
            child: _error != null
                ? Row(
                    key: ValueKey(_error),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(LucideIcons.circleAlert, size: 14, color: GColors.destructive),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: GText.xs(color: GColors.destructive))),
                    ],
                  )
                : Text(
                    'Используйте поле, только если знаете, откуда взять токен.',
                    key: const ValueKey('hint'),
                    style: GText.xs(color: GColors.mutedForeground),
                  ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: GColors.background,
      body: SafeArea(
        child: Column(
          children: [
            SignalBuilder(
              builder: (context) {
                final custom = isDesktop && customTitlebarSignal();
                final bar = SizedBox(
                  height: 56,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        if (widget.addingAccount)
                          GButton(
                            label: 'Отмена',
                            icon: LucideIcons.arrowLeft,
                            variant: GButtonVariant.ghost,
                            size: GButtonSize.sm,
                            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
                          ),
                        const Spacer(),
                        if (custom && !widget.addingAccount) const WindowButtons(),
                      ],
                    ),
                  ),
                );
                return custom ? DragToMoveArea(child: bar) : bar;
              },
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
                  child: card,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
