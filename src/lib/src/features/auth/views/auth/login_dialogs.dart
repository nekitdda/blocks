import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_all/webview_all.dart';
import 'package:youmuz/src/ui/ui.dart';

// Sign-in flows. Each dialog pops with the OAuth token it obtained (or null
// when closed); the sign-in screen decides what to do with it.

class YandexLoginDialog extends StatefulWidget {
  final bool fullscreen;

  const YandexLoginDialog({super.key, this.fullscreen = false});

  @override
  State<YandexLoginDialog> createState() => _YandexLoginDialogState();
}

class _YandexLoginDialogState extends State<YandexLoginDialog> {
  late final WebViewController _controller;
  bool _isFinalized = false;
  bool _isFetchingToken = false;
  static final _tokenRegExp = RegExp('access_token=(y0_[^&]+)');

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    unawaited(_controller.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(
      _controller.setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      ),
    );
    unawaited(
      _controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) async {
            unawaited(_parseToken(url));
          },
          onUrlChange: (change) async {
            if (change.url != null) {
              unawaited(_parseToken(change.url!));
            }
          },
          onNavigationRequest: (request) async {
            return await _parseToken(request.url);
          },
          onPageFinished: (url) async {
            unawaited(_parseToken(url));
            final currentUrl = await _controller.currentUrl();
            if (currentUrl != null) {
              unawaited(_parseToken(currentUrl));
            }
          },
        ),
      ),
    );
    unawaited(
      _controller.loadRequest(
        Uri.parse('https://passport.yandex.ru/pwl-yandex/auth/'),
      ),
    );
  }

  /// Strip secrets before logging a URL.
  ///
  /// This method is called from every navigation callback, and the branch it
  /// exists to detect is the OAuth redirect that carries `access_token`. The
  /// raw URL was being `debugPrint`ed, which lands in logcat / stdout and is
  /// world-readable on pre-4.1 Android and in any crash report.
  static String _redactUrl(String url) {
    return url.replaceAll(RegExp(r'((?:access_token|oauth_token|token)=)[^&\s]+', caseSensitive: false), r'$1<redacted>');
  }

  Future<NavigationDecision> _parseToken(String urlString) async {
    if (_isFinalized) return NavigationDecision.navigate;

    debugPrint('🌐 URL: ${_redactUrl(urlString)}');

    // 1. Intercept from URL (OAuth redirect)
    final match = _tokenRegExp.firstMatch(urlString);
    if (match != null) {
      final token = match.group(1);
      if (token != null) {
        await _handleFoundToken(token);
        return NavigationDecision.prevent;
      }
    }

    // 2. Fetch token if already in profile but not yet authorized
    if (!_isFetchingToken &&
        (urlString.startsWith('https://id.yandex.ru') ||
            urlString.startsWith('https://passport.yandex.ru/profile'))) {
      debugPrint('🔍 Authorized! Getting token via official desktop client...');
      _isFetchingToken = true;

      unawaited(
        _controller.loadRequest(
          Uri.parse(
            'https://oauth.yandex.ru/authorize?response_type=token&client_id=97fe03033fa34407ac9bcf91d5afed5b',
          ),
        ),
      );

      return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  Future<void> _handleFoundToken(String token) async {
    if (_isFinalized) return;
    _isFinalized = true;
    if (mounted) Navigator.of(context).pop(token);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fullscreen) {
      return Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: const Text('Вход через Яндекс'),
        ),
        body: WebViewWidget(controller: _controller),
      );
    }
    final size = MediaQuery.sizeOf(context);
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: (size.width - 48).clamp(320.0, 1000.0),
          height: (size.height - 48).clamp(360.0, 800.0),
          decoration: BoxDecoration(
            color: GColors.card,
            borderRadius: BorderRadius.circular(GRadius.x3l),
            border: Border.all(color: GColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                child: Row(
                  children: [
                    const Icon(LucideIcons.globe, size: 16, color: GColors.mutedForeground),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Вход через Яндекс', style: GText.sm(weight: GText.medium))),
                    GButton(
                      label: 'Сбросить браузер',
                      icon: LucideIcons.trash2,
                      variant: GButtonVariant.ghost,
                      size: GButtonSize.sm,
                      onPressed: () async {
                        await WebViewCookieManager().clearCookies();
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                    const SizedBox(width: 4),
                    GIconButton(
                      icon: LucideIcons.x,
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const GDivider(),
              Expanded(child: WebViewWidget(controller: _controller)),
            ],
          ),
        ),
      ),
    );
  }
}

class YandexDeviceLoginDialog extends StatefulWidget {
  final bool fullscreen;

  const YandexDeviceLoginDialog({super.key, this.fullscreen = false});

  @override
  State<YandexDeviceLoginDialog> createState() =>
      _YandexDeviceLoginDialogState();
}

class _YandexDeviceLoginDialogState extends State<YandexDeviceLoginDialog> {
  String? _userCode;
  String? _deviceCode;
  String? _verificationUrl;
  int _interval = 5;
  Timer? _timer;
  bool _isLoading = true;
  String? _error;
  bool _isFinalized = false;
  /// Set in `dispose`. Distinct from `mounted` because the poll timer is armed
  /// from *after* an `await`, at which point `dispose` may already have run.
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initDeviceFlow());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initDeviceFlow() async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('https://oauth.yandex.ru/device/code'),
      );
      request.headers.set('content-type', 'application/x-www-form-urlencoded');
      request.write('client_id=23cabbbdc6cd418abb4b39c32c41195d');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      // Every `setState` below is reached after an `await`, so the dialog may
      // already be closed: `setState() called after dispose()` otherwise.
      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          setState(() {
            _error = 'Ответ сервера не распознан.';
            _isLoading = false;
          });
          return;
        }
        setState(() {
          _userCode = decoded['user_code'] as String?;
          _deviceCode = decoded['device_code'] as String?;
          _verificationUrl = decoded['verification_url'] as String?;
          _interval = (decoded['interval'] as num?)?.toInt() ?? 5;
          _isLoading = false;
        });
        _startPolling();
      } else {
        setState(() {
          _error = 'Не удалось получить код устройства от Яндекс.';
          _isLoading = false;
        });
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка сети: $e';
        _isLoading = false;
      });
    } finally {
      client.close();
    }
  }

  void _startPolling() {
    // `dispose` already ran if the dialog was closed during the device-code
    // request; starting the timer then would poll for the life of the process
    // with no way to cancel it.
    if (!mounted || _disposed) return;
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: _interval), (timer) {
      unawaited(_pollToken());
    });
  }

  Future<void> _pollToken() async {
    if (_isFinalized || _deviceCode == null || _disposed) return;

    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('https://oauth.yandex.ru/token'),
      );
      request.headers.set('content-type', 'application/x-www-form-urlencoded');
      request.write(
        'grant_type=device_code'
        '&client_id=23cabbbdc6cd418abb4b39c32c41195d'
        '&client_secret=53bc75238f0c4d08a118e51fe9203300'
        '&code=$_deviceCode',
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (_disposed) return;
      final decoded = jsonDecode(body);
      // A captive portal or proxy returning HTML used to throw a cast error
      // that was only `debugPrint`ed, leaving the poller ticking every 5s
      // forever with no user-visible error.
      if (decoded is! Map<String, dynamic>) {
        _timer?.cancel();
        if (mounted) {
          setState(() => _error = 'Ответ сервера не распознан.');
        }
        return;
      }
      final data = decoded;

      if (response.statusCode == 200) {
        final token = data['access_token'] as String?;
        if (token != null) {
          _timer?.cancel();
          await _handleFoundToken(token);
        }
      } else {
        final error = data['error'] as String?;
        if (error != 'authorization_pending') {
          _timer?.cancel();
          if (mounted) {
            setState(() {
              _error =
                  data['error_description'] as String? ??
                  'Ошибка авторизации ($error).';
            });
          }
        }
      }
    } on Object catch (e) {
      debugPrint('Error polling token: $e');
    } finally {
      client.close();
    }
  }

  Future<void> _handleFoundToken(String token) async {
    if (_isFinalized) return;
    _isFinalized = true;
    if (mounted) Navigator.of(context).pop(token);
  }

  void _openBrowser() {
    final url = _verificationUrl ?? 'https://ya.ru/device';
    unawaited(
      () async {
        try {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        } on Object catch (e) {
          debugPrint('Error launching browser: $e');
        }
      }(),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_isLoading) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GLoader(padding: 12),
          Text('Получение кода авторизации...', style: GText.sm(color: GColors.mutedForeground)),
        ],
      );
    } else if (_error != null) {
      content = GEmptyState(
        icon: LucideIcons.circleAlert,
        title: 'Не удалось войти',
        message: _error,
        compact: true,
        action: GButton(
          label: 'Повторить',
          variant: GButtonVariant.secondary,
          onPressed: () {
            setState(() {
              _isLoading = true;
              _error = null;
            });
            unawaited(_initDeviceFlow());
          },
        ),
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Откройте ya.ru/device на любом устройстве, где вы вошли в Яндекс, и введите код:',
            textAlign: TextAlign.center,
            style: GText.sm(color: GColors.mutedForeground),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            decoration: BoxDecoration(
              color: GColors.secondary,
              borderRadius: BorderRadius.circular(GRadius.x2l),
            ),
            child: SelectableText(
              _userCode ?? '',
              style: GText.style(32, weight: GText.semibold, mono: true).copyWith(letterSpacing: 6),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              GButton(
                label: 'Копировать код',
                icon: LucideIcons.copy,
                variant: GButtonVariant.secondary,
                onPressed: () async {
                  if (_userCode != null) {
                    await Clipboard.setData(ClipboardData(text: _userCode!));
                  }
                },
              ),
              GButton(
                label: 'Открыть ya.ru/device',
                icon: LucideIcons.externalLink,
                onPressed: _openBrowser,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: GColors.brand),
              ),
              const SizedBox(width: 10),
              Text('Ожидание подтверждения на сайте', style: GText.xs(color: GColors.mutedForeground)),
            ],
          ),
        ],
      );
    }

    if (widget.fullscreen) {
      return Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: const Text('Вход по коду устройства'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: content,
          ),
        ),
      );
    }
    return GDialog(
      title: 'Вход по коду устройства',
      width: 460,
      content: content,
    );
  }
}
