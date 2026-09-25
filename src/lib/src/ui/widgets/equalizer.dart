import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/ui/tokens.dart';

/// Three bouncing bars marking the playing track (`animate-eq`: 0.9s,
/// staggered 0/0.2/0.4s, scaleY 0.3..1 from the bottom). Static at half
/// height when paused.
class GEqualizer extends StatefulWidget {
  const GEqualizer({
    required this.playing,
    super.key,
    this.color = GColors.brand,
    this.height = 12,
  });

  final bool playing;
  final Color color;
  final double height;

  @override
  State<GEqualizer> createState() => _GEqualizerState();
}

class _GEqualizerState extends State<GEqualizer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(GEqualizer old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ExcludeSemantics(
      child: SizedBox(
        width: 3 * 3 + 2 * 2,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _EqPainter(
                t: _controller.value,
                playing: widget.playing && !reduceMotion,
                color: widget.color,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EqPainter extends CustomPainter {
  _EqPainter({required this.t, required this.playing, required this.color});

  final double t;
  final bool playing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const delays = [0.0, 0.2, 0.4];
    for (var i = 0; i < 3; i++) {
      double scale = 0.5;
      if (playing) {
        // ease-in-out between 0.3 and 1 and back over one period.
        final phase = ((t - delays[i] / 0.9) % 1 + 1) % 1;
        final wave = (1 - math.cos(phase * 2 * math.pi)) / 2;
        scale = 0.3 + 0.7 * wave;
      }
      final h = size.height * scale;
      canvas.drawRect(Rect.fromLTWH(i * 5.0, size.height - h, 3, h), paint);
    }
  }

  @override
  bool shouldRepaint(_EqPainter old) =>
      old.t != t || old.playing != playing || old.color != color;
}
