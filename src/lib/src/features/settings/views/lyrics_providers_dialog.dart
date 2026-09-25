import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/features/auth/providers/auth_provider.dart';
import 'package:youmuz/src/features/core/providers/notification_provider.dart';
import 'package:youmuz/src/features/playback/providers/lyrics_provider.dart';
import 'package:youmuz/src/rust/api/content.dart' as rust;
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Lets the user disable individual lyrics sources. The order they're
/// queried in is fixed (word-synced-capable sources first) and isn't
/// user-editable — this only controls which ones participate at all.
class LyricsProvidersDialog extends StatefulWidget {
  const LyricsProvidersDialog({super.key});

  static void show(BuildContext context) {
    unawaited(
      showGDialog<void>(
        context,
        builder: (context) => const LyricsProvidersDialog(),
      ),
    );
  }

  @override
  State<LyricsProvidersDialog> createState() => _LyricsProvidersDialogState();
}

class _LyricsProvidersDialogState extends State<LyricsProvidersDialog> {
  List<LyricsProviderSettingDto>? _providers;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final ctx = appContextSignal.value;
    if (ctx == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }
    try {
      final providers = await rust.getLyricsProviderSettings(ctx: ctx);
      if (!mounted) return;
      setState(() {
        _providers = providers;
        _loading = false;
        _failed = false;
      });
    } on Object catch (e) {
      debugPrint('Failed to load lyrics providers: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _failed = false;
    });
    unawaited(_load());
  }

  Future<void> _toggle(LyricsProviderSettingDto provider, bool enabled) async {
    final ctx = appContextSignal.value;
    if (ctx == null || _providers == null) return;

    _setEnabled(provider.id, enabled);
    try {
      await rust.setLyricsProviderEnabled(
        ctx: ctx,
        id: provider.id,
        isEnabledFlag: enabled,
      );
      clearLyricsCache();
    } on Object catch (e) {
      if (mounted) _setEnabled(provider.id, !enabled);
      showAppError('Не удалось сохранить источник: $e');
    }
  }

  void _setEnabled(String id, bool enabled) {
    final providers = _providers;
    if (providers == null) return;
    final index = providers.indexWhere((p) => p.id == id);
    if (index == -1) return;
    final current = providers[index];
    setState(() {
      _providers = [...providers]
        ..[index] = LyricsProviderSettingDto(
          id: current.id,
          name: current.name,
          enabled: enabled,
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    return GDialog(
      title: 'Источники текста песен',
      description:
          'Отключённые источники не используются при поиске текста. Порядок '
          'поиска фиксированный: сначала — источники с синхронизацией по '
          'словам.',
      width: 480,
      content: _buildContent(),
      actions: [
        GButton(label: 'Готово', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const SizedBox(height: 160, child: GLoader(padding: 0));
    }
    final providers = _providers;
    if (_failed || providers == null) {
      return GEmptyState(
        icon: LucideIcons.circleAlert,
        title: 'Не удалось загрузить источники',
        message: 'Попробуйте ещё раз.',
        compact: true,
        action: GButton(
          label: 'Повторить',
          size: GButtonSize.sm,
          variant: GButtonVariant.secondary,
          onPressed: _retry,
        ),
      );
    }
    if (providers.isEmpty) {
      return const GEmptyState(
        icon: LucideIcons.micVocal,
        title: 'Источники не найдены',
        compact: true,
      );
    }
    return SingleChildScrollView(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GRadius.xl),
          border: Border.all(color: GColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(GRadius.xl - 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < providers.length; i++) ...[
                if (i > 0) const GDivider(),
                _ProviderRow(
                  provider: providers[i],
                  onChanged: (enabled) =>
                      unawaited(_toggle(providers[i], enabled)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({required this.provider, required this.onChanged});

  final LyricsProviderSettingDto provider;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GPressable(
      onTap: () => onChanged(!provider.enabled),
      builder: (context, s) => AnimatedContainer(
        duration: GDurations.fast,
        curve: GCurves.standard,
        color: s.highlighted ? GColors.secondary : const Color(0x00000000),
        foregroundDecoration: s.focused
            ? const BoxDecoration(
                border: Border.fromBorderSide(BorderSide(color: GColors.ring)),
              )
            : null,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                provider.name,
                style: GText.sm(
                  weight: GText.medium,
                  color: provider.enabled
                      ? GColors.foreground
                      : GColors.mutedForeground,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // The row is the focus target (Space/Enter toggles); GPressable
            // only reports hover while focusable.
            ExcludeFocus(
              child: Switch(value: provider.enabled, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}
