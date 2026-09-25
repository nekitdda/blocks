import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Album / playlist / artist page after the reference playlist page:
/// `grid lg:grid-cols-[360px_1fr] gap-10` with the cover, title, stats and
/// actions in a column that stays in place while the tracks scroll.
class CollectionPage extends StatelessWidget {
  const CollectionPage({
    required this.cover,
    required this.kindLabel,
    required this.title,
    required this.slivers,
    super.key,
    this.description,
    this.stats = const [],
    this.primaryAction,
    this.actions = const [],
    this.footer,
    this.scrollController,
  });

  /// Square image; sized by the page.
  final Widget Function(double size) cover;
  final String kindLabel;
  final String title;
  final Widget? description;
  final List<(String, String)> stats;
  final Widget? primaryAction;
  final List<Widget> actions;
  final String? footer;
  final List<Widget> slivers;
  final ScrollController? scrollController;

  Widget _header(BuildContext context, {required bool wide, required double coverSize}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        cover(coverSize),
        const SizedBox(height: 24),
        Text(kindLabel, style: GText.sm(color: GColors.mutedForeground)),
        const SizedBox(height: 4),
        Text(title, style: GText.display(wide ? 48 : 36).copyWith(height: 1.05)),
        if (description != null) ...[
          const SizedBox(height: 12),
          DefaultTextStyle(
            style: GText.sm(color: GColors.mutedForeground).copyWith(height: 1.6),
            child: description!,
          ),
        ],
        if (stats.isNotEmpty) ...[
          const SizedBox(height: 24),
          GStatGrid(items: stats),
        ],
        if (primaryAction != null || actions.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              if (primaryAction != null) Expanded(child: primaryAction!),
              for (final a in actions) ...[const SizedBox(width: 8), a],
            ],
          ),
        ],
        if (footer != null) ...[
          const SizedBox(height: 16),
          Text(footer!, style: GText.xs(color: GColors.mutedForeground)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= GLayout.wideBreakpoint;
        final padding = GLayout.pagePadding(width);

        if (!wide) {
          return Scrollbar(
            controller: scrollController,
            child: CustomScrollView(
              controller: scrollController,
              primary: scrollController == null,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, 32),
                  sliver: SliverToBoxAdapter(
                    child: _header(context, wide: false, coverSize: 224),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding.left - 8, 0, padding.right - 8, 32),
                  sliver: SliverMainAxisGroup(slivers: slivers),
                ),
              ],
            ),
          );
        }

        final contentWidth = width.clamp(0.0, GLayout.maxContentWidth);
        return Center(
          child: SizedBox(
            width: contentWidth,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 360 + padding.left,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(padding.left, 32, 0, 32),
                    child: _header(context, wide: true, coverSize: 360),
                  ),
                ),
                const SizedBox(width: 40),
                Expanded(
                  child: Scrollbar(
                    controller: scrollController,
                    child: CustomScrollView(
                      controller: scrollController,
                      primary: scrollController == null,
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(0, 32, padding.right, 32),
                          sliver: SliverMainAxisGroup(slivers: slivers),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "Слушать" pill (`h-12 rounded-full bg-foreground text-sm font-medium`).
class ListenButton extends StatelessWidget {
  const ListenButton({required this.onPressed, super.key, this.isPlaying = false, this.label});

  final VoidCallback? onPressed;
  final bool isPlaying;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return GButton(
      label: label ?? (isPlaying ? 'Пауза' : 'Слушать'),
      glyph: isPlaying ? GGlyphKind.pause : GGlyphKind.play,
      size: GButtonSize.lg,
      expand: true,
      onPressed: onPressed,
    );
  }
}
