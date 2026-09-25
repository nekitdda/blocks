import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/core/views/widgets/audio_settings.dart';
import 'package:youmuz/src/features/playback/providers/playback_provider.dart';
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Output quality picker.
///
/// The default constructor is the compact player control: an icon button
/// opening a menu with the current stream codec, the quality options and the
/// audio settings. [CommonQualitySelector.segmented] is the inline chip row
/// used inside the audio settings.
class CommonQualitySelector extends SignalWidget {
  /// Colour of the active quality code in the menu; defaults to the brand.
  final Color? accentColor;
  final double iconSize;
  final bool segmented;

  const CommonQualitySelector({this.accentColor, super.key, this.iconSize = 16})
    : segmented = false;

  const CommonQualitySelector.segmented({super.key})
    : accentColor = null,
      iconSize = 16,
      segmented = true;

  static const List<({AudioQuality quality, String label, String code})>
  _options = [
    (quality: AudioQuality.low, label: 'Низкое', code: 'LQ'),
    (quality: AudioQuality.normal, label: 'Стандартное', code: 'NQ'),
    (quality: AudioQuality.high, label: 'Высокое', code: 'HQ'),
  ];

  @override
  Widget build(BuildContext context) {
    if (segmented) {
      final current = audioQualitySignal.value;
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final option in _options)
            GChip(
              label: option.label,
              active: current == option.quality,
              onPressed: () =>
                  unawaited(PlaybackController.setQuality(option.quality)),
            ),
        ],
      );
    }

    return GMenu(
      items: () => _menuItems(context),
      builder: (context, menu) => GIconButton(
        icon: LucideIcons.gauge,
        size: iconSize,
        tooltip: 'Качество звука',
        onPressed: () => menu.open(),
      ),
    );
  }

  List<GMenuItem> _menuItems(BuildContext context) {
    final current = audioQualitySignal.value;
    final codec = trackMetadataSignal.value.codec;
    final activeColor = accentColor ?? GColors.brand;

    return [
      if (codec != null) ...[
        GMenuItem(
          label: 'Поток: ${codec.toUpperCase()}',
          icon: LucideIcons.info,
          enabled: false,
        ),
        const GMenuItem.divider(),
      ],
      for (final option in _options)
        GMenuItem(
          label: '${option.label} качество',
          leading: _QualityCode(
            option.code,
            color: current == option.quality ? activeColor : null,
          ),
          checked: current == option.quality,
          onSelected: () =>
              unawaited(PlaybackController.setQuality(option.quality)),
        ),
      const GMenuItem.divider(),
      GMenuItem(
        label: 'Настройки звука',
        icon: LucideIcons.slidersHorizontal,
        onSelected: () {
          if (context.mounted) unawaited(AudioSettingsDialog.show(context));
        },
      ),
    ];
  }
}

/// `LQ` / `NQ` / `HQ` tag in the icon slot of a quality menu row.
class _QualityCode extends StatelessWidget {
  final String code;
  final Color? color;

  const _QualityCode(this.code, {this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      child: Text(
        code,
        style: GText.style(
          10,
          lineHeight: 16,
          weight: GText.semibold,
          color: color ?? GColors.mutedForeground,
          mono: true,
        ),
      ),
    );
  }
}
