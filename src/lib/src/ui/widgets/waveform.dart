import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/ui/tokens.dart';

/// Bar heights (0..1) derived from [seed], identical to the reference.
List<double> waveformBars(String seed, int count) {
  var h = 0;
  for (final rune in seed.runes) {
    final unit = rune > 0xFFFF ? ((rune - 0x10000) >> 10) + 0xD800 : rune;
    h = (h * 31 + unit) & 0xFFFFFFFF;
  }
  return List<double>.generate(count, (i) {
    h = (h * 1103515245 + 12345) & 0xFFFFFFFF;
    final noise = (h % 1000) / 1000;
    final envelope = math.sin((i / count) * math.pi) * 0.55 + 0.35;
    return math.max(0.12, math.min(1, envelope * (0.5 + noise * 0.8)));
  });
}

/// Waveform used instead of a progress bar: rounded bars with a 3px gap,
/// played bars in foreground, the rest at 20%. Click or drag to seek; arrow
/// keys move by 2%.
class GWaveform extends StatefulWidget {
  const GWaveform({
    required this.seed,
    required this.progress,
    super.key,
    this.count = 72,
    this.height = 32,
    this.gap = 3,
    this.onSeek,
  });

  final String seed;

  /// 0..1.
  final double progress;
  final int count;
  final double height;
  final double gap;

  /// Receives the target position as a 0..1 ratio. Null makes it read-only.
  final ValueChanged<double>? onSeek;

  @override
  State<GWaveform> createState() => _GWaveformState();
}

class _GWaveformState extends State<GWaveform> {
  late List<double> _bars = waveformBars(widget.seed, widget.count);
  double? _dragRatio;
  double? _hoverRatio;
  bool _focused = false;

  @override
  void didUpdateWidget(GWaveform old) {
    super.didUpdateWidget(old);
    if (old.seed != widget.seed || old.count != widget.count) {
      _bars = waveformBars(widget.seed, widget.count);
    }
  }

  double _ratioAt(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0);

  void _nudge(double delta) {
    widget.onSeek?.call((widget.progress + delta).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onSeek != null;
    final shown = _dragRatio ?? widget.progress;

    Widget paint = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final bars = CustomPaint(
          size: Size(width, widget.height),
          painter: _WaveformPainter(
            bars: _bars,
            progress: shown.isFinite ? shown.clamp(0.0, 1.0) : 0,
            hover: interactive ? _hoverRatio : null,
            gap: widget.gap,
          ),
        );
        if (!interactive) return bars;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (e) => setState(() => _hoverRatio = _ratioAt(e.localPosition, width)),
          onExit: (_) => setState(() => _hoverRatio = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => widget.onSeek!(_ratioAt(d.localPosition, width)),
            onHorizontalDragStart: (d) =>
                setState(() => _dragRatio = _ratioAt(d.localPosition, width)),
            onHorizontalDragUpdate: (d) =>
                setState(() => _dragRatio = _ratioAt(d.localPosition, width)),
            onHorizontalDragEnd: (_) {
              final r = _dragRatio;
              setState(() => _dragRatio = null);
              if (r != null) widget.onSeek!(r);
            },
            onHorizontalDragCancel: () => setState(() => _dragRatio = null),
            child: bars,
          ),
        );
      },
    );

    paint = SizedBox(height: widget.height, child: paint);
    if (!interactive) return ExcludeSemantics(child: paint);

    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowRight): _SeekIntent(0.02),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _SeekIntent(-0.02),
      },
      actions: {
        _SeekIntent: CallbackAction<_SeekIntent>(
          onInvoke: (i) {
            _nudge(i.delta);
            return null;
          },
        ),
      },
      child: Semantics(
        slider: true,
        label: 'Позиция трека',
        value: '${(widget.progress * 100).round()}%',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _focused ? GColors.ring : const Color(0x00000000),
            ),
          ),
          child: paint,
        ),
      ),
    );
  }
}

class _SeekIntent extends Intent {
  const _SeekIntent(this.delta);
  final double delta;
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.hover,
    required this.gap,
  });

  final List<double> bars;
  final double progress;
  final double? hover;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final n = bars.length;
    if (n == 0 || size.width <= 0) return;
    final barWidth = math.max(1.0, (size.width - gap * (n - 1)) / n);
    final played = Paint()..color = GColors.foreground;
    final rest = Paint()..color = GColors.foreground20;
    final preview = Paint()..color = GColors.foreground.withValues(alpha: 0.45);

    for (var i = 0; i < n; i++) {
      final ratio = i / n;
      final h = size.height * bars[i];
      final x = i * (barWidth + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, (size.height - h) / 2, barWidth, h),
        Radius.circular(barWidth / 2),
      );
      final Paint paint;
      if (ratio < progress) {
        paint = played;
      } else if (hover != null && ratio < hover!) {
        paint = preview;
      } else {
        paint = rest;
      }
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.hover != hover ||
      !identical(old.bars, bars) ||
      old.gap != gap;
}
