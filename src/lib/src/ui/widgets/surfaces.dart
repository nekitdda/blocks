import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/ui/tokens.dart';
import 'package:youmuz/src/ui/widgets/pressable.dart';

/// Card surface (`rounded-2xl bg-card`). With [onTap] it lightens to
/// `bg-secondary` on hover.
class GCard extends StatelessWidget {
  const GCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(16),
    this.radius = GRadius.x2l,
    this.onTap,
    this.onSecondaryTapUp,
    this.color = GColors.card,
    this.hoverColor = GColors.secondary,
    this.border = false,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final void Function(TapUpDetails details)? onSecondaryTapUp;
  final Color color;
  final Color hoverColor;
  final bool border;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (onTap == null && onSecondaryTapUp == null) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: border ? Border.all(color: GColors.border) : null,
        ),
        child: child,
      );
    }
    return GPressable(
      onTap: onTap,
      onSecondaryTapUp: onSecondaryTapUp,
      semanticLabel: semanticLabel,
      builder: (context, s) => AnimatedContainer(
        duration: GDurations.fast,
        curve: GCurves.standard,
        padding: padding,
        decoration: BoxDecoration(
          color: s.hovered ? hoverColor : color,
          borderRadius: BorderRadius.circular(radius),
          border: s.focused
              ? Border.all(color: GColors.ring)
              : (border ? Border.all(color: GColors.border) : null),
        ),
        child: child,
      ),
    );
  }
}

/// Centers page content at `max-w-7xl` with the page padding.
class GPageFrame extends StatelessWidget {
  const GPageFrame({required this.child, super.key, this.padding, this.maxWidth});

  final Widget child;
  final EdgeInsets? padding;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? GLayout.maxContentWidth),
        // Full available width, so start-aligned content sits on the left
        // edge of the frame instead of shrink-wrapping to the center.
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: padding ?? GLayout.pagePadding(width),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Scrollable page body. [bottomInset] keeps the last rows clear of the
/// floating player bar.
class GScrollPage extends StatelessWidget {
  const GScrollPage({
    required this.children,
    super.key,
    this.controller,
    this.padding,
    this.maxWidth,
    this.bottomInset = 24,
  });

  final List<Widget> children;
  final ScrollController? controller;
  final EdgeInsets? padding;
  final double? maxWidth;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final base = padding ?? GLayout.pagePadding(width);
    return Scrollbar(
      controller: controller,
      child: SingleChildScrollView(
        controller: controller,
        primary: controller == null,
        child: GPageFrame(
          maxWidth: maxWidth,
          padding: base.copyWith(bottom: base.bottom + bottomInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Section heading (`text-xl font-semibold tracking-tight`) with an
/// optional trailing action.
class GSectionHeader extends StatelessWidget {
  const GSectionHeader(this.title, {super.key, this.trailing, this.bottom = 16});

  final String title;
  final Widget? trailing;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: GText.sectionTitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Empty / error state: icon in a `bg-secondary` circle, title and hint.
class GEmptyState extends StatelessWidget {
  const GEmptyState({
    required this.icon,
    required this.title,
    super.key,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 24 : 56, horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(color: GColors.secondary, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: GColors.mutedForeground),
              ),
              const SizedBox(height: 16),
              Text(title, style: GText.sm(weight: GText.medium), textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(
                  message!,
                  style: GText.xs(color: GColors.mutedForeground),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Quiet loading indicator.
class GLoader extends StatelessWidget {
  const GLoader({super.key, this.size = 20, this.padding = 48});

  final double size;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Center(
        child: SizedBox.square(
          dimension: size,
          child: const CircularProgressIndicator(strokeWidth: 2, color: GColors.mutedForeground),
        ),
      ),
    );
  }
}

/// Flat placeholder block (no shimmer: the style avoids glow effects).
class GSkeleton extends StatelessWidget {
  const GSkeleton({super.key, this.width, this.height = 14, this.radius = GRadius.md});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: GColors.secondary,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Stats strip: `grid gap-px rounded-2xl bg-border`, cells `bg-card px-2 py-3`.
class GStatGrid extends StatelessWidget {
  const GStatGrid({required this.items, super.key});

  final List<(String label, String value)> items;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(GRadius.x2l),
      child: ColoredBox(
        color: GColors.border,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 1),
              Expanded(
                child: Container(
                  color: GColors.card,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Column(
                    children: [
                      Text(items[i].$1, style: GText.style(11, lineHeight: 16, color: GColors.mutedForeground)),
                      const SizedBox(height: 2),
                      Text(
                        items[i].$2,
                        style: GText.sm(weight: GText.medium),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Explicit-content badge (`rounded bg-accent px-1 text-[10px]`).
class GExplicitBadge extends StatelessWidget {
  const GExplicitBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(color: GColors.accent, borderRadius: BorderRadius.circular(4)),
      child: Text('E', style: GText.style(10, lineHeight: 14)),
    );
  }
}

/// Small label pill, e.g. "Плюс" or "Активен".
class GBadge extends StatelessWidget {
  const GBadge(this.label, {super.key, this.brand = false});

  final String label;
  final bool brand;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: brand ? GColors.brand.withValues(alpha: 0.14) : GColors.accent,
        borderRadius: BorderRadius.circular(GRadius.full),
      ),
      child: Text(
        label,
        style: GText.style(10.5, lineHeight: 16, weight: GText.medium, color: brand ? GColors.brand : GColors.mutedForeground),
      ),
    );
  }
}

/// Hairline divider in `border` color.
class GDivider extends StatelessWidget {
  const GDivider({super.key, this.vertical = false, this.indent = 0});

  final bool vertical;
  final double indent;

  @override
  Widget build(BuildContext context) {
    return vertical
        ? Container(width: 1, margin: EdgeInsets.symmetric(vertical: indent), color: GColors.border)
        : Container(height: 1, margin: EdgeInsets.symmetric(horizontal: indent), color: GColors.border);
  }
}
