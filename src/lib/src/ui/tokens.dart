/// Graphite design tokens: a warm dark interface without glow or gradients,
/// monochrome with a muted amber accent. Values follow the reference
/// (`.theme-graphite`, Tailwind scale, radius base 0.625rem).
library;

import 'dart:ui';

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

abstract final class GColors {
  static const background = Color(0xFF121211);
  static const foreground = Color(0xFFECEBE6);
  static const card = Color(0xFF1A1A18);
  static const popover = Color(0xFF1A1A18);
  static const secondary = Color(0xFF222220);
  static const muted = Color(0xFF1E1E1C);
  static const mutedForeground = Color(0xFF8B8880);
  static const accent = Color(0xFF252523);
  static const border = Color(0xFF2A2927);
  static const input = Color(0xFF2A2927);
  static const ring = Color(0xFFD9A441);
  static const brand = Color(0xFFD9A441);
  static const brandForeground = Color(0xFF121211);
  static const destructive = Color(0xFFFF6467);

  /// `bg-background/60`: overlay on covers (hover play button).
  static const coverOverlay = Color(0x99121211);

  /// `bg-foreground/20`: unplayed waveform bars, slider tracks.
  static const foreground20 = Color(0x33ECEBE6);

  /// Modal barrier.
  static const scrim = Color(0xB3000000);
}

/// Corner radii (`--radius: 0.625rem`).
abstract final class GRadius {
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 14;
  static const double x2l = 18;
  static const double x3l = 22;
  static const double full = 999;
}

abstract final class GDurations {
  /// Tailwind `transition-colors` default.
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 320);
}

abstract final class GCurves {
  /// `cubic-bezier(0.4, 0, 0.2, 1)`.
  static const standard = Cubic(0.4, 0, 0.2, 1);
  static const emphasized = Cubic(0.2, 0, 0, 1);
}

abstract final class GFonts {
  static const sans = 'Onest';
  static const mono = 'JetBrainsMono';
}

/// Text styles on the Tailwind type scale. The bundled fonts are variable,
/// so each weight is also passed as a `wght` variation.
abstract final class GText {
  static TextStyle style(
    double size, {
    double lineHeight = 0,
    FontWeight weight = FontWeight.w400,
    Color color = GColors.foreground,
    bool tight = false,
    bool mono = false,
  }) {
    return TextStyle(
      fontFamily: mono ? GFonts.mono : GFonts.sans,
      fontSize: size,
      height: lineHeight > 0 ? lineHeight / size : null,
      fontWeight: weight,
      fontVariations: [FontVariation.weight(weight.value.toDouble())],
      letterSpacing: tight ? -0.025 * size : 0,
      color: color,
      fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
    );
  }

  /// `text-xs` 12/16.
  static TextStyle xs({FontWeight weight = FontWeight.w400, Color color = GColors.foreground}) =>
      style(12, lineHeight: 16, weight: weight, color: color);

  /// `text-sm` 14/20.
  static TextStyle sm({FontWeight weight = FontWeight.w400, Color color = GColors.foreground}) =>
      style(14, lineHeight: 20, weight: weight, color: color);

  /// `text-base` 16/24.
  static TextStyle base({FontWeight weight = FontWeight.w400, Color color = GColors.foreground}) =>
      style(16, lineHeight: 24, weight: weight, color: color);

  /// `text-lg` 18/28.
  static TextStyle lg({FontWeight weight = FontWeight.w400, Color color = GColors.foreground}) =>
      style(18, lineHeight: 28, weight: weight, color: color);

  /// `text-xl font-semibold tracking-tight`: section titles.
  static TextStyle sectionTitle({Color color = GColors.foreground}) =>
      style(20, lineHeight: 28, weight: FontWeight.w600, color: color, tight: true);

  /// `text-3xl`/`text-4xl font-semibold tracking-tight`: card headlines.
  static TextStyle headline(double size, {Color color = GColors.foreground}) =>
      style(size, lineHeight: size * 1.1, weight: FontWeight.w600, color: color, tight: true);

  /// `text-5xl`..`text-8xl` display titles, `leading-[0.95]`.
  static TextStyle display(double size, {Color color = GColors.foreground}) =>
      style(size, lineHeight: size * 0.95, weight: FontWeight.w600, color: color, tight: true);

  /// `font-mono text-[11px] tabular-nums`: timestamps.
  static TextStyle time({double size = 11, Color color = GColors.mutedForeground}) =>
      style(size, lineHeight: size * 1.45, color: color, mono: true);

  static const medium = FontWeight.w500;
  static const semibold = FontWeight.w600;
}

abstract final class GLayout {
  /// `max-w-7xl`.
  static const double maxContentWidth = 1280;

  /// `h-16`.
  static const double headerHeight = 64;

  /// Below this width the touch layout is used.
  static const double compactBreakpoint = 600;

  /// `lg:` breakpoint (sidebars, two-column pages).
  static const double wideBreakpoint = 1024;

  /// `md:` breakpoint.
  static const double mediumBreakpoint = 768;

  static EdgeInsets pagePadding(double width) => width >= mediumBreakpoint
      ? const EdgeInsets.fromLTRB(32, 32, 32, 32)
      : const EdgeInsets.fromLTRB(16, 24, 16, 24);
}
