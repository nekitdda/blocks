import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/core/views/widgets/quality_selector.dart';
import 'package:youmuz/src/features/playback/providers/playback_provider.dart';
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Output quality, equalizer and DSP effects in one panel: a bottom sheet on
/// Android ([bottomSheet]), a dialog elsewhere. [show] picks the right one.
class AudioSettingsDialog extends StatelessWidget {
  final bool bottomSheet;

  const AudioSettingsDialog({super.key, this.bottomSheet = false});

  /// Refreshes the equalizer and effect state, then opens the panel.
  static Future<void> show(BuildContext context) {
    unawaited(refreshEqualizer());
    unawaited(refreshAudioEffects());
    if (Platform.isAndroid) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const AudioSettingsDialog(bottomSheet: true),
      );
    }
    return showGDialog<void>(
      context,
      builder: (_) => const AudioSettingsDialog(),
    );
  }

  static const _sections = <Widget>[
    _QualitySection(),
    _SectionDivider(),
    _EqualizerSection(),
    _SectionDivider(),
    _EffectsSection(),
  ];

  @override
  Widget build(BuildContext context) {
    final sliderTheme = SliderTheme.of(
      context,
    ).copyWith(tickMarkShape: SliderTickMarkShape.noTickMark);

    if (bottomSheet) {
      return SliderTheme(
        data: sliderTheme,
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          snap: true,
          expand: false,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              Text('Настройки звука', style: GText.lg(weight: GText.semibold)),
              const SizedBox(height: 20),
              ..._sections,
            ],
          ),
        ),
      );
    }

    return SliderTheme(
      data: sliderTheme,
      child: GDialog(
        title: 'Настройки звука',
        width: 680,
        content: const SingleChildScrollView(
          // Keeps the desktop scrollbar clear of the switches.
          padding: EdgeInsets.only(right: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _sections,
          ),
        ),
        actions: [
          GButton(
            label: 'Закрыть',
            variant: GButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: GDivider(),
    );
  }
}

/// `text-sm font-medium` title with an optional status line and controls.
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// Shows [subtitle] in the brand colour (e.g. "Включён").
  final bool subtitleActive;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.subtitleActive = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: GText.sm(weight: GText.medium)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: GText.xs(
                    color: subtitleActive
                        ? GColors.brand
                        : GColors.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _QualitySection extends StatelessWidget {
  const _QualitySection();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final codec = trackMetadataSignal.value.codec;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: 'Качество звука',
              trailing: codec == null
                  ? null
                  : GBadge('Поток: ${codec.toUpperCase()}'),
            ),
            const SizedBox(height: 12),
            const CommonQualitySelector.segmented(),
          ],
        );
      },
    );
  }
}

class _EqualizerSection extends StatelessWidget {
  const _EqualizerSection();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final eq = equalizerSignal.value;
        final enabled = eq?.enabled ?? false;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: 'Эквалайзер',
              subtitle: eq == null ? null : (enabled ? 'Включён' : 'Выключен'),
              subtitleActive: enabled,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GButton(
                    label: 'Сбросить',
                    icon: LucideIcons.rotateCcw,
                    variant: GButtonVariant.ghost,
                    size: GButtonSize.sm,
                    onPressed: eq == null
                        ? null
                        : () => unawaited(PlaybackController.resetEqualizer()),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: enabled,
                    onChanged: eq == null
                        ? null
                        : (value) => unawaited(
                            PlaybackController.setEqualizerEnabled(
                              enabled: value,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (eq == null)
              const GLoader(padding: 32)
            else
              AnimatedOpacity(
                duration: GDurations.medium,
                curve: GCurves.standard,
                opacity: enabled ? 1 : 0.5,
                child: _EqualizerBands(bands: eq.bands, enabled: enabled),
              ),
          ],
        );
      },
    );
  }
}

const double _eqMinGain = -12;
const double _eqMaxGain = 12;

/// Height of the gain label above and the frequency label below each band.
const double _eqLabelBlock = 20;

/// Theme thumb radius: the slider track starts this far inside its box.
const double _eqTrackInset = 6;

/// Vertical offset of [gain] inside a band slider area of [height].
double _gainY(double gain, double height) {
  final t = (gain - _eqMinGain) / (_eqMaxGain - _eqMinGain);
  return _eqTrackInset + (1 - t) * (height - 2 * _eqTrackInset);
}

String _formatGain(double gain) {
  if (gain.abs() < 0.05) return '0.0';
  return '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)}';
}

String _formatFreq(double freq) {
  if (freq >= 1000) {
    return '${(freq / 1000).toStringAsFixed(freq % 1000 == 0 ? 0 : 1)}к';
  }
  return '${freq.toInt()}';
}

Widget _bandSlider(BandDto band, double gain, {required bool enabled}) {
  return Slider(
    value: gain,
    min: _eqMinGain,
    max: _eqMaxGain,
    semanticFormatterCallback: (value) =>
        '${band.frequency.round()} Гц: ${_formatGain(value)} дБ',
    onChanged: enabled
        ? (value) =>
              unawaited(PlaybackController.setEqualizerBand(band.index, value))
        : null,
  );
}

class _EqualizerBands extends StatelessWidget {
  final List<BandDto> bands;
  final bool enabled;

  const _EqualizerBands({required this.bands, required this.enabled});

  static const double _rulerWidth = 28;
  static const double _minBandWidth = 34;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitsColumns =
            constraints.maxWidth >=
            _rulerWidth + 8 + _minBandWidth * bands.length;

        if (!fitsColumns) {
          // Narrow (touch) layouts get one horizontal slider per band, which
          // also keeps band drags from fighting the sheet's vertical scroll.
          return Column(
            children: [
              for (final band in bands) _BandRow(band: band, enabled: enabled),
            ],
          );
        }

        return SizedBox(
          height: 208,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: _rulerWidth, child: _GainRuler()),
              const SizedBox(width: 8),
              Expanded(
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: _BandBlocks(
                        child: CustomPaint(painter: _GainGridPainter()),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final band in bands)
                          Expanded(
                            child: _BandColumn(band: band, enabled: enabled),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Reserves the label rows above and below, so the ruler, grid and band
/// sliders share one vertical scale.
class _BandBlocks extends StatelessWidget {
  final Widget child;

  const _BandBlocks({required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: _eqLabelBlock),
        Expanded(child: child),
        const SizedBox(height: _eqLabelBlock),
      ],
    );
  }
}

class _GainRuler extends StatelessWidget {
  const _GainRuler();

  static const List<({double gain, String label})> _marks = [
    (gain: 12.0, label: '+12'),
    (gain: 6.0, label: '+6'),
    (gain: 0.0, label: '0'),
    (gain: -6.0, label: '-6'),
    (gain: -12.0, label: '-12'),
  ];

  @override
  Widget build(BuildContext context) {
    final style = GText.time(size: 10);
    final halfLine = (style.fontSize! * style.height!) / 2;
    return _BandBlocks(
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          clipBehavior: Clip.none,
          children: [
            for (final mark in _marks)
              Positioned(
                right: 0,
                top: _gainY(mark.gain, constraints.maxHeight) - halfLine,
                child: Text(mark.label, style: style),
              ),
          ],
        ),
      ),
    );
  }
}

/// Hairlines at ±12, ±6 and 0 dB; the 0 dB line is a step brighter.
class _GainGridPainter extends CustomPainter {
  const _GainGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = GColors.border
      ..strokeWidth = 1;
    final zero = Paint()
      ..color = GColors.foreground20
      ..strokeWidth = 1;
    for (final gain in const [12.0, 6.0, 0.0, -6.0, -12.0]) {
      final y = _gainY(gain, size.height).roundToDouble() + 0.5;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gain == 0 ? zero : line,
      );
    }
  }

  @override
  bool shouldRepaint(_GainGridPainter oldDelegate) => false;
}

/// Vertical band: gain above, slider, frequency below.
class _BandColumn extends StatelessWidget {
  final BandDto band;
  final bool enabled;

  const _BandColumn({required this.band, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final gain = band.gainDb.clamp(_eqMinGain, _eqMaxGain);
    final boosted = enabled && gain.abs() >= 0.05;

    return Column(
      children: [
        SizedBox(
          height: _eqLabelBlock,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _formatGain(gain),
                style: GText.time(
                  size: 10,
                  color: boosted ? GColors.brand : GColors.mutedForeground,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          // Quarter turns 3: the slider's minimum ends up at the bottom.
          child: RotatedBox(
            quarterTurns: 3,
            child: _bandSlider(band, gain, enabled: enabled),
          ),
        ),
        SizedBox(
          height: _eqLabelBlock,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _formatFreq(band.frequency),
                style: GText.time(size: 10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Horizontal band for narrow layouts: frequency, slider, gain.
class _BandRow extends StatelessWidget {
  final BandDto band;
  final bool enabled;

  const _BandRow({required this.band, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final gain = band.gainDb.clamp(_eqMinGain, _eqMaxGain);
    final boosted = enabled && gain.abs() >= 0.05;

    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(_formatFreq(band.frequency), style: GText.time()),
          ),
          Expanded(child: _bandSlider(band, gain, enabled: enabled)),
          SizedBox(
            width: 44,
            child: Text(
              _formatGain(gain),
              textAlign: TextAlign.right,
              style: GText.time(
                color: boosted ? GColors.brand : GColors.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EffectsSection extends StatelessWidget {
  const _EffectsSection();

  // Matches the effect ids registered in src/rust/src/audio/fx/init.rs.
  static const _icons = <String, IconData>{
    'chorus': LucideIcons.waves, // layered, wavering pitch
    'lowpass': LucideIcons.arrowDownToLine, // lets lows through
    'highpass': LucideIcons.arrowUpToLine, // lets highs through
    'bandpass': LucideIcons.arrowLeftRight, // passes a band, cuts both sides
    'notch': LucideIcons.minus, // cuts a thin band out
    'dc_block': LucideIcons.foldVertical, // flattens the DC offset
    'reverb': LucideIcons.radar, // diffuse, spatial reflections
    'delay': LucideIcons.repeat, // repeating echoes
    'compressor': LucideIcons.shrink, // squeezes dynamic range
    'overdrive': LucideIcons.zap, // driven/distorted signal
  };

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final effects = audioEffectsSignal.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader(
              title: 'Эффекты',
              subtitle: 'Обработка сигнала (DSP)',
            ),
            const SizedBox(height: 8),
            if (effects.isEmpty)
              const GLoader(padding: 32)
            else
              for (final effect in effects)
                _EffectTile(
                  key: ValueKey(effect.id),
                  effect: effect,
                  icon: _icons[effect.id] ?? LucideIcons.slidersHorizontal,
                ),
          ],
        );
      },
    );
  }
}

/// Effect row (`rounded-xl`, hover `bg-secondary`); tapping it unfolds the
/// parameters on a `bg-secondary` panel.
class _EffectTile extends StatefulWidget {
  final AudioEffectDto effect;
  final IconData icon;

  const _EffectTile({required this.effect, required this.icon, super.key});

  @override
  State<_EffectTile> createState() => _EffectTileState();
}

class _EffectTileState extends State<_EffectTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final effect = widget.effect;
    final enabled = effect.enabled;

    return AnimatedContainer(
      duration: GDurations.fast,
      curve: GCurves.standard,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: _expanded ? GColors.secondary : const Color(0x00000000),
        borderRadius: BorderRadius.circular(GRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GPressable(
            onTap: () => setState(() => _expanded = !_expanded),
            semanticLabel: effect.name,
            builder: (context, s) => AnimatedContainer(
              duration: GDurations.fast,
              curve: GCurves.standard,
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: !_expanded && s.hovered
                    ? GColors.secondary
                    : const Color(0x00000000),
                borderRadius: BorderRadius.circular(GRadius.xl),
                border: Border.all(
                  color: s.focused ? GColors.ring : const Color(0x00000000),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    size: 16,
                    color: enabled ? GColors.brand : GColors.mutedForeground,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          effect.name,
                          style: GText.sm(weight: GText.medium),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          enabled ? 'Включён' : 'Выключен',
                          style: GText.xs(
                            color: enabled
                                ? GColors.brand
                                : GColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: enabled,
                    onChanged: (value) => unawaited(
                      PlaybackController.setEffectEnabled(
                        effect.id,
                        enabled: value,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    duration: GDurations.medium,
                    curve: GCurves.standard,
                    turns: _expanded ? 0.5 : 0,
                    child: Icon(
                      LucideIcons.chevronDown,
                      size: 16,
                      color: s.hovered
                          ? GColors.foreground
                          : GColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: GDurations.medium,
            curve: GCurves.standard,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const GDivider(),
                        const SizedBox(height: 8),
                        for (final param in effect.params)
                          _EffectParamRow(
                            param: param,
                            enabled: enabled,
                            onChanged: (value) => unawaited(
                              PlaybackController.setEffectParam(
                                effect.id,
                                param.index,
                                value,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GButton(
                            label: 'Сбросить параметры',
                            icon: LucideIcons.rotateCcw,
                            variant: GButtonVariant.ghost,
                            size: GButtonSize.sm,
                            onPressed: () => unawaited(
                              PlaybackController.resetEffect(effect.id),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _EffectParamRow extends StatelessWidget {
  final EffectParamDto param;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _EffectParamRow({
    required this.param,
    required this.enabled,
    required this.onChanged,
  });

  String _format(double value) => '${value.toStringAsFixed(1)}${param.unit}';

  @override
  Widget build(BuildContext context) {
    final isDefault = (param.value - param.defaultValue).abs() < 0.001;
    // Rounded: e.g. (1 - 0) / 0.1 is 9.999… in floating point.
    final steps = param.step > 0
        ? ((param.max - param.min) / param.step).round()
        : 0;

    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              param.name,
              style: GText.xs(color: GColors.mutedForeground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Slider(
              value: param.value.clamp(param.min, param.max),
              min: param.min,
              max: param.max,
              divisions: steps > 0 ? steps : null,
              semanticFormatterCallback: (value) =>
                  '${param.name}: ${_format(value)}',
              onChanged: enabled ? onChanged : null,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              _format(param.value),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GText.time(
                color: isDefault ? GColors.mutedForeground : GColors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EqualizerDialog extends StatelessWidget {
  const EqualizerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return const AudioSettingsDialog();
  }
}
