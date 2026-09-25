import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/ui/tokens.dart';

/// Filled glyphs (`fill-current`) drawn from the Lucide outlines, which the
/// icon font can only render stroked.
enum GGlyphKind { play, pause, skipBack, skipForward, heart }

class GGlyph extends StatelessWidget {
  const GGlyph(
    this.kind, {
    super.key,
    this.size = 16,
    this.color = GColors.foreground,
    this.filled = true,
  });

  final GGlyphKind kind;
  final double size;
  final Color color;

  /// Heart only: outline when false.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _GlyphPainter(kind, color, filled),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.kind, this.color, this.filled);

  final GGlyphKind kind;
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    // Lucide viewBox is 24x24 with a 2px round stroke.
    final scale = size.width / 24;
    canvas.scale(scale);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (kind) {
      case GGlyphKind.play:
        final p = Path()
          ..moveTo(6, 3.5)
          ..lineTo(19.5, 12)
          ..lineTo(6, 20.5)
          ..close();
        canvas
          ..drawPath(p, fill)
          ..drawPath(p, stroke);
      case GGlyphKind.pause:
        for (final x in [6.0, 14.0]) {
          final r = RRect.fromRectAndRadius(
            Rect.fromLTWH(x, 4, 4, 16),
            const Radius.circular(1),
          );
          canvas
            ..drawRRect(r, fill)
            ..drawRRect(r, stroke);
        }
      case GGlyphKind.skipBack:
        final p = Path()
          ..moveTo(19, 20)
          ..lineTo(9, 12)
          ..lineTo(19, 4)
          ..close();
        canvas
          ..drawPath(p, fill)
          ..drawPath(p, stroke)
          ..drawLine(const Offset(5, 19), const Offset(5, 5), stroke);
      case GGlyphKind.skipForward:
        final p = Path()
          ..moveTo(5, 4)
          ..lineTo(15, 12)
          ..lineTo(5, 20)
          ..close();
        canvas
          ..drawPath(p, fill)
          ..drawPath(p, stroke)
          ..drawLine(const Offset(19, 5), const Offset(19, 19), stroke);
      case GGlyphKind.heart:
        final p = _heart();
        if (filled) canvas.drawPath(p, fill);
        canvas.drawPath(p, stroke);
    }
  }

  /// Lucide `heart`.
  static Path _heart() {
    return Path()
      ..moveTo(2, 9.5)
      ..arcToPoint(const Offset(11.591, 5.824), radius: const Radius.circular(5.5))
      ..arcToPoint(
        const Offset(12.409, 5.824),
        radius: const Radius.circular(0.56),
        clockwise: false,
      )
      ..arcToPoint(const Offset(22, 9.5), radius: const Radius.circular(5.5))
      ..cubicTo(22, 11.79, 20.5, 13.5, 19, 15)
      ..lineTo(13.508, 20.313)
      ..arcToPoint(const Offset(10.508, 20.332), radius: const Radius.circular(2))
      ..lineTo(5, 15)
      ..cubicTo(3.5, 13.5, 2, 11.8, 2, 9.5)
      ..close();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.kind != kind || old.color != color || old.filled != filled;
}
