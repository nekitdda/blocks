import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/ui/tokens.dart';
import 'package:youmuz/src/ui/widgets/glyphs.dart';
import 'package:youmuz/src/ui/widgets/pressable.dart';

enum GButtonVariant {
  /// `bg-foreground text-background`.
  primary,

  /// `bg-secondary`, hover `bg-accent`.
  secondary,

  /// Transparent, hover `bg-secondary`.
  ghost,

  /// `bg-brand text-brand-foreground`.
  brand,

  /// Secondary surface with destructive text.
  destructive,
}

enum GButtonSize { sm, md, lg }

/// Pill button (`rounded-full`), optionally with a leading icon.
class GButton extends StatelessWidget {
  const GButton({
    required this.label,
    super.key,
    this.onPressed,
    this.icon,
    this.glyph,
    this.variant = GButtonVariant.primary,
    this.size = GButtonSize.md,
    this.expand = false,
    this.loading = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final GGlyphKind? glyph;
  final GButtonVariant variant;
  final GButtonSize size;
  final bool expand;
  final bool loading;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final height = switch (size) {
      GButtonSize.sm => 32.0,
      GButtonSize.md => 40.0,
      GButtonSize.lg => 48.0,
    };
    final hPad = switch (size) {
      GButtonSize.sm => 12.0,
      GButtonSize.md => 16.0,
      GButtonSize.lg => 24.0,
    };
    final enabled = onPressed != null && !loading;

    return GPressable(
      onTap: enabled ? onPressed : null,
      tooltip: tooltip,
      semanticLabel: label,
      builder: (context, s) {
        final (bg, fg) = _colors(s);
        final textStyle = (size == GButtonSize.sm ? GText.xs : GText.sm)(
          weight: GText.medium,
          color: fg,
        );
        final iconSize = size == GButtonSize.sm ? 14.0 : 16.0;
        Widget? leading;
        if (loading) {
          leading = SizedBox.square(
            dimension: iconSize,
            child: CircularProgressIndicator(strokeWidth: 1.8, color: fg),
          );
        } else if (glyph != null) {
          leading = GGlyph(glyph!, size: iconSize, color: fg);
        } else if (icon != null) {
          leading = Icon(icon, size: iconSize, color: fg);
        }

        final content = Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 8)],
            Flexible(
              child: Text(
                label,
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );

        return GPressScale(
          pressed: s.pressed,
          child: GFocusRing(
            visible: s.focused,
            child: AnimatedContainer(
              duration: GDurations.fast,
              curve: GCurves.standard,
              height: height,
              padding: EdgeInsets.symmetric(horizontal: hPad),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(GRadius.full),
              ),
              child: Opacity(opacity: enabled ? 1 : 0.5, child: content),
            ),
          ),
        );
      },
    );
  }

  (Color, Color) _colors(GStates s) {
    switch (variant) {
      case GButtonVariant.primary:
        return (
          s.hovered ? const Color(0xFFD9D8D2) : GColors.foreground,
          GColors.background,
        );
      case GButtonVariant.secondary:
        return (s.hovered ? GColors.accent : GColors.secondary, GColors.foreground);
      case GButtonVariant.ghost:
        return (
          s.hovered ? GColors.secondary : const Color(0x00000000),
          s.hovered ? GColors.foreground : GColors.mutedForeground,
        );
      case GButtonVariant.brand:
        return (
          s.hovered ? const Color(0xFFE2B259) : GColors.brand,
          GColors.brandForeground,
        );
      case GButtonVariant.destructive:
        return (s.hovered ? GColors.accent : GColors.secondary, GColors.destructive);
    }
  }
}

enum GCircleVariant {
  /// `bg-secondary text-muted-foreground`, hover `bg-accent text-foreground`.
  secondary,

  /// Like [secondary] with the icon always in foreground.
  strong,

  /// `bg-foreground text-background`.
  primary,
}

/// Round icon button (`grid size-10 place-items-center rounded-full`).
class GCircleButton extends StatelessWidget {
  const GCircleButton({
    required this.onPressed,
    super.key,
    this.icon,
    this.glyph,
    this.size = 40,
    this.iconSize = 16,
    this.tooltip,
    this.variant = GCircleVariant.secondary,
    this.active = false,
    this.activeColor = GColors.brand,
  });

  final VoidCallback? onPressed;
  final IconData? icon;
  final GGlyphKind? glyph;
  final double size;
  final double iconSize;
  final String? tooltip;
  final GCircleVariant variant;

  /// Toggle on (e.g. liked): icon in [activeColor].
  final bool active;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return GPressable(
      onTap: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      selected: active,
      builder: (context, s) {
        final Color bg;
        Color fg;
        switch (variant) {
          case GCircleVariant.primary:
            bg = s.hovered ? const Color(0xFFD9D8D2) : GColors.foreground;
            fg = GColors.background;
          case GCircleVariant.secondary:
            bg = s.hovered ? GColors.accent : GColors.secondary;
            fg = s.hovered ? GColors.foreground : GColors.mutedForeground;
          case GCircleVariant.strong:
            bg = s.hovered ? GColors.accent : GColors.secondary;
            fg = GColors.foreground;
        }
        if (active) fg = activeColor;
        final child = glyph != null
            ? GGlyph(
                glyph!,
                size: iconSize,
                color: fg,
                filled: glyph != GGlyphKind.heart || active,
              )
            : Icon(icon, size: iconSize, color: fg);
        return GPressScale(
          pressed: s.pressed,
          child: AnimatedContainer(
            duration: GDurations.fast,
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: s.focused ? Border.all(color: GColors.ring) : null,
            ),
            child: Opacity(opacity: onPressed == null ? 0.5 : 1, child: child),
          ),
        );
      },
    );
  }
}

/// Ghost icon button (`p-2 text-muted-foreground hover:text-foreground`).
class GIconButton extends StatelessWidget {
  const GIconButton({
    required this.onPressed,
    super.key,
    this.icon,
    this.glyph,
    this.size = 16,
    this.padding = 8,
    this.tooltip,
    this.active = false,
    this.activeColor = GColors.brand,
    this.color = GColors.mutedForeground,
    this.hoverColor = GColors.foreground,
    this.background = false,
  });

  final VoidCallback? onPressed;
  final IconData? icon;
  final GGlyphKind? glyph;
  final double size;
  final double padding;
  final String? tooltip;
  final bool active;
  final Color activeColor;
  final Color color;
  final Color hoverColor;

  /// Hover also paints a `bg-secondary` circle.
  final bool background;

  @override
  Widget build(BuildContext context) {
    return GPressable(
      onTap: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      selected: active,
      builder: (context, s) {
        final fg = active
            ? activeColor
            : (s.hovered || s.focused ? hoverColor : color);
        final child = glyph != null
            ? GGlyph(
                glyph!,
                size: size,
                color: fg,
                filled: glyph != GGlyphKind.heart || active,
              )
            : Icon(icon, size: size, color: fg);
        return GPressScale(
          pressed: s.pressed,
          scale: 0.9,
          child: AnimatedContainer(
            duration: GDurations.fast,
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: background && s.hovered ? GColors.secondary : const Color(0x00000000),
              shape: BoxShape.circle,
              border: s.focused ? Border.all(color: GColors.ring) : null,
            ),
            child: Opacity(opacity: onPressed == null ? 0.4 : 1, child: child),
          ),
        );
      },
    );
  }
}

/// Play/pause button: `rounded-full bg-foreground text-background`.
class GPlayButton extends StatelessWidget {
  const GPlayButton({
    required this.isPlaying,
    required this.onPressed,
    super.key,
    this.size = 40,
    this.iconSize = 16,
    this.loading = false,
  });

  final bool isPlaying;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GPressable(
      onTap: onPressed,
      tooltip: isPlaying ? 'Пауза' : 'Играть',
      semanticLabel: isPlaying ? 'Пауза' : 'Играть',
      builder: (context, s) {
        return GPressScale(
          pressed: s.pressed,
          child: AnimatedContainer(
            duration: GDurations.fast,
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: s.hovered ? const Color(0xFFD9D8D2) : GColors.foreground,
              shape: BoxShape.circle,
              border: s.focused ? Border.all(color: GColors.ring, width: 2) : null,
            ),
            child: loading
                ? SizedBox.square(
                    dimension: iconSize,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: GColors.background,
                    ),
                  )
                : Padding(
                    // `ml-0.5` optical centering of the play triangle.
                    padding: EdgeInsets.only(left: isPlaying ? 0 : iconSize * 0.12),
                    child: AnimatedSwitcher(
                      duration: GDurations.fast,
                      child: GGlyph(
                        isPlaying ? GGlyphKind.pause : GGlyphKind.play,
                        key: ValueKey(isPlaying),
                        size: iconSize,
                        color: GColors.background,
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// Option chip (`rounded-lg bg-secondary px-3 py-1.5 text-sm`); active chips
/// invert to `bg-foreground text-background`.
class GChip extends StatelessWidget {
  const GChip({
    required this.label,
    required this.onPressed,
    super.key,
    this.active = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GPressable(
      onTap: onPressed,
      selected: active,
      semanticLabel: label,
      builder: (context, s) {
        final fg = active
            ? GColors.background
            : (s.hovered ? GColors.foreground : GColors.mutedForeground);
        return GPressScale(
          pressed: s.pressed,
          scale: 0.97,
          child: AnimatedContainer(
            duration: GDurations.fast,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active ? GColors.foreground : GColors.secondary,
              borderRadius: BorderRadius.circular(GRadius.lg),
              border: s.focused ? Border.all(color: GColors.ring) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(label, style: GText.sm(color: fg)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Navigation pill (`rounded-full px-3.5 py-1.5 text-sm`), active
/// `bg-secondary text-foreground`.
class GNavPill extends StatelessWidget {
  const GNavPill({
    required this.label,
    required this.onPressed,
    super.key,
    this.active = false,
    this.icon,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return GPressable(
      onTap: onPressed,
      selected: active,
      semanticLabel: label,
      builder: (context, s) {
        final fg = active || s.hovered ? GColors.foreground : GColors.mutedForeground;
        return AnimatedContainer(
          duration: GDurations.fast,
          curve: GCurves.standard,
          padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 14, vertical: 6),
          decoration: BoxDecoration(
            color: active ? GColors.secondary : const Color(0x00000000),
            borderRadius: BorderRadius.circular(GRadius.full),
            border: s.focused ? Border.all(color: GColors.ring) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label, style: GText.sm(color: fg)),
            ],
          ),
        );
      },
    );
  }
}

/// Inline text action (`text-sm text-muted-foreground hover:text-foreground`).
class GTextAction extends StatelessWidget {
  const GTextAction({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.style,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return GPressable(
      onTap: onPressed,
      semanticLabel: label,
      builder: (context, s) {
        final color = s.hovered || s.focused ? GColors.foreground : GColors.mutedForeground;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: (style ?? GText.sm()).copyWith(color: color)),
            if (icon != null) ...[
              const SizedBox(width: 4),
              Icon(icon, size: 14, color: color),
            ],
          ],
        );
      },
    );
  }
}
