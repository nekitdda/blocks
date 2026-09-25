import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Grid card: square cover (`rounded-2xl`, dims on hover), title
/// (`text-sm font-medium mt-3`) and subtitle (`text-xs muted`).
class MediaTile extends StatelessWidget {
  const MediaTile({
    required this.title,
    required this.onTap,
    super.key,
    this.coverUrl,
    this.subtitle,
    this.circle = false,
    this.icon = LucideIcons.music2,
    this.menu,
    this.cover,
  });

  final String title;
  final String? subtitle;
  final String? coverUrl;
  final VoidCallback? onTap;
  final bool circle;
  final IconData icon;
  final List<GMenuItem> Function()? menu;

  /// Replaces the image (e.g. the "Мне нравится" tile).
  final Widget? cover;

  @override
  Widget build(BuildContext context) {
    Widget tile(GMenuHandle? handle) => GPressable(
      onTap: onTap,
      onSecondaryTapUp: handle == null ? null : (d) => handle.open(position: d.localPosition),
      onLongPressStart: handle == null ? null : (d) => handle.open(position: d.localPosition),
      semanticLabel: title,
      builder: (context, s) => Column(
        crossAxisAlignment: circle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: AnimatedOpacity(
              duration: GDurations.fast,
              opacity: s.hovered ? 0.8 : 1,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  shape: circle ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: circle ? null : BorderRadius.circular(GRadius.x2l),
                  border: s.focused ? Border.all(color: GColors.ring, width: 2) : null,
                ),
                child: cover ??
                    LayoutBuilder(
                      builder: (context, c) => GCover(
                        url: coverUrl,
                        size: c.maxWidth,
                        radius: GRadius.x2l,
                        circle: circle,
                        icon: icon,
                      ),
                    ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: circle ? TextAlign.center : TextAlign.start,
            style: GText.sm(weight: GText.medium),
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: circle ? TextAlign.center : TextAlign.start,
              style: GText.xs(color: GColors.mutedForeground),
            ),
        ],
      ),
    );

    if (menu == null) return tile(null);
    return GMenu(
      items: menu!,
      alignmentOffset: Offset.zero,
      builder: (context, handle) => tile(handle),
    );
  }
}

/// Responsive card grid (6 columns at `md`, fewer on narrow screens).
class MediaGrid extends StatelessWidget {
  const MediaGrid({
    required this.children,
    super.key,
    this.maxColumns = 6,
    this.minTileWidth = 150,
    this.spacing = 16,
    this.runSpacing = 24,
  });

  final List<Widget> children;
  final int maxColumns;
  final double minTileWidth;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = ((width + spacing) / (minTileWidth + spacing)).floor().clamp(2, maxColumns);
        final tileWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children) SizedBox(width: tileWidth, child: child),
          ],
        );
      },
    );
  }
}

/// Horizontal list tile for compact grids (`rounded-2xl bg-card p-2 pr-3`,
/// 56px cover): "my playlists" on the home page.
class CompactMediaTile extends StatelessWidget {
  const CompactMediaTile({
    required this.title,
    required this.onTap,
    super.key,
    this.subtitle,
    this.coverUrl,
    this.cover,
    this.card = true,
    this.coverSize = 56,
  });

  final String title;
  final String? subtitle;
  final String? coverUrl;
  final Widget? cover;
  final VoidCallback? onTap;
  final bool card;
  final double coverSize;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        cover ?? GCover(url: coverUrl, size: coverSize, radius: GRadius.xl),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GText.sm(weight: GText.medium)),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GText.xs(color: GColors.mutedForeground),
                ),
            ],
          ),
        ),
      ],
    );
    if (!card) {
      return GPressable(
        onTap: onTap,
        semanticLabel: title,
        builder: (context, s) => AnimatedOpacity(
          duration: GDurations.fast,
          opacity: s.hovered ? 0.8 : 1,
          child: content,
        ),
      );
    }
    return GCard(
      onTap: onTap,
      semanticLabel: title,
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: content,
    );
  }
}

/// Cover for "Мне нравится": amber heart on a card tile.
class LikedCover extends StatelessWidget {
  const LikedCover({super.key, this.size, this.radius = GRadius.x2l});

  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final side = size ?? c.maxWidth;
        return Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            color: GColors.accent,
            borderRadius: BorderRadius.circular(radius),
          ),
          alignment: Alignment.center,
          child: GGlyph(GGlyphKind.heart, size: side * 0.36, color: GColors.brand),
        );
      },
    );
  }
}
