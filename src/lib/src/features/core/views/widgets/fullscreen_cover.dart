import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/features/core/views/widgets/rust_cached_image.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Cover art over a flat dark scrim. Tap anywhere, Esc or the close button
/// dismisses it.
class FullscreenCoverDialog extends StatelessWidget {
  final String imageUrl;
  final String heroTag;

  /// Lower-resolution copy shown while [imageUrl] loads; falls back to
  /// [heroTag], which callers set to the original cover URL.
  final String? placeholderUrl;

  const FullscreenCoverDialog({
    required this.imageUrl,
    required this.heroTag,
    this.placeholderUrl,
    super.key,
  });

  static Future<void> show(
    BuildContext context,
    String imageUrl, {
    String? heroTag,
  }) {
    // Fullscreen always wants the largest preset the backend offers.
    final highResUrl = resolveCoverUrl(imageUrl, coverSizePicks.last);

    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: GColors.background.withValues(alpha: 0.94),
        barrierDismissible: true,
        barrierLabel: 'Закрыть',
        transitionDuration: GDurations.slow,
        reverseTransitionDuration: GDurations.medium,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: GCurves.standard,
            ),
            child: FullscreenCoverDialog(
              imageUrl: highResUrl,
              heroTag: heroTag ?? imageUrl,
              placeholderUrl: imageUrl,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The already-cached low-res cover keeps the frame filled while the
    // high-res version loads.
    final placeholder = RustCachedImage(imageUrl: placeholderUrl ?? heroTag);
    void close() => Navigator.of(context).pop();

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: close,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: Center(
                    child: ConstrainedBox(
                      // The largest cover preset is 1000px.
                      constraints: const BoxConstraints(
                        maxWidth: 960,
                        maxHeight: 960,
                      ),
                      child: Hero(
                        tag: heroTag,
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(GRadius.x3l),
                            child: RustCachedImage(
                              imageUrl: imageUrl,
                              placeholder: placeholder,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: GIconButton(
                icon: LucideIcons.x,
                tooltip: 'Закрыть',
                size: 20,
                padding: 10,
                background: true,
                onPressed: close,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
