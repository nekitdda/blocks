import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youmuz/src/features/settings/services/update_service.dart';
import 'package:youmuz/src/ui/ui.dart';

final _bulletPattern = RegExp(r'^[-*+]\s+');

class UpdateDialog extends StatefulWidget {
  final AppUpdateInfo? initialInfo;
  final bool bottomSheet;

  const UpdateDialog({this.initialInfo, this.bottomSheet = false, super.key});

  static void show(BuildContext context, {AppUpdateInfo? initialInfo}) {
    if (Platform.isAndroid) {
      // Shape, drag handle and barrier come from the bottom sheet theme.
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) =>
              UpdateDialog(initialInfo: initialInfo, bottomSheet: true),
        ),
      );
      return;
    }
    unawaited(
      showGDialog<void>(
        context,
        builder: (context) => UpdateDialog(initialInfo: initialInfo),
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isLoading = false;
  String? _error;
  AppUpdateInfo? _info;

  @override
  void initState() {
    super.initState();
    if (widget.initialInfo != null) {
      _info = widget.initialInfo;
    } else {
      _isLoading = true;
      unawaited(_fetchUpdateInfo());
    }
  }

  void _checkUpdates() {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    unawaited(_fetchUpdateInfo());
  }

  Future<void> _fetchUpdateInfo() async {
    final info = await UpdateService.checkForUpdates();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (info == null) {
        _error = 'Проверьте интернет-соединение.';
      } else {
        _info = info;
      }
    });
  }

  void _launchUrl(String url) {
    unawaited(() async {
      try {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } on Object catch (e) {
        debugPrint('Error launching browser: $e');
      }
    }());
  }

  /// Minimal Markdown: `#` headings, `-`/`*` bullets, `**` stripped.
  Widget _buildChangelog(String changelog) {
    final children = <Widget>[];

    for (final line in changelog.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        children.add(const SizedBox(height: 8));
        continue;
      }

      if (trimmed.startsWith('#')) {
        final depth = trimmed.indexOf(RegExp('[^#]'));
        if (depth == -1) continue;
        final style = switch (depth) {
          1 => GText.base(weight: GText.semibold),
          2 => GText.sm(weight: GText.semibold),
          _ => GText.sm(weight: GText.medium),
        };
        children.add(
          Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 0 : 12, bottom: 6),
            child: Text(
              trimmed.substring(depth).trim().replaceAll('**', ''),
              style: style,
            ),
          ),
        );
      } else if (_bulletPattern.hasMatch(trimmed)) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 16,
                  child: Text(
                    '•',
                    style: GText.sm(color: GColors.mutedForeground),
                  ),
                ),
                Expanded(
                  child: Text(
                    trimmed
                        .replaceFirst(_bulletPattern, '')
                        .replaceAll('**', ''),
                    style: GText.sm(color: GColors.mutedForeground),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              trimmed.replaceAll('**', ''),
              style: GText.sm(color: GColors.mutedForeground),
            ),
          ),
        );
      }
    }

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _closeButton(String label, {bool primary = false}) {
    return GButton(
      label: label,
      variant: primary ? GButtonVariant.primary : GButtonVariant.secondary,
      onPressed: () => Navigator.pop(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    Widget content;
    var actions = <Widget>[];

    if (_isLoading) {
      content = const _LoadingBlock();
    } else if (_error != null) {
      content = _StatusBlock(
        icon: LucideIcons.circleAlert,
        iconColor: GColors.destructive,
        title: 'Не удалось проверить обновления',
        message: _error,
      );
      actions = [
        if (!widget.bottomSheet) _closeButton('Закрыть'),
        GButton(
          label: 'Повторить',
          icon: LucideIcons.refreshCw,
          onPressed: _checkUpdates,
        ),
      ];
    } else if (info != null && info.hasUpdate) {
      content = ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Список изменений в этой версии:',
              style: GText.xs(
                weight: GText.medium,
                color: GColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: GColors.background,
                  borderRadius: BorderRadius.circular(GRadius.xl),
                  border: Border.all(color: GColors.border),
                ),
                child: SingleChildScrollView(
                  child: _buildChangelog(info.changelog),
                ),
              ),
            ),
          ],
        ),
      );
      actions = [
        if (!widget.bottomSheet) _closeButton('Закрыть'),
        GButton(
          label: 'Скачать обновление',
          icon: LucideIcons.download,
          onPressed: () => _launchUrl(info.url),
        ),
      ];
    } else if (info != null) {
      content = _StatusBlock(
        icon: LucideIcons.circleCheck,
        iconColor: GColors.brand,
        title: 'У вас установлена последняя версия',
        message: 'Текущая версия: ${info.latestVersion}',
      );
      actions = [
        if (!widget.bottomSheet) _closeButton('Отлично', primary: true),
      ];
    } else {
      content = const SizedBox.shrink();
    }

    final titleText = info != null && info.hasUpdate
        ? 'Доступно обновление до версии ${info.latestVersion}'
        : 'Обновление программы';

    if (widget.bottomSheet) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(titleText, style: GText.lg(weight: GText.semibold)),
                const SizedBox(height: 16),
                Flexible(child: content),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return GDialog(
      title: titleText,
      width: 520,
      content: content,
      actions: actions,
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: GColors.mutedForeground,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Проверяем наличие обновлений…',
            style: GText.xs(color: GColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// Result state: icon in a `bg-secondary` circle, title and hint.
class _StatusBlock extends StatelessWidget {
  const _StatusBlock({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.message,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: GColors.secondary,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GText.base(weight: GText.semibold),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: GText.sm(color: GColors.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}
