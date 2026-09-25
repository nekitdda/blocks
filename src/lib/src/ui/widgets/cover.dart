import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/features/core/views/widgets/rust_cached_image.dart';
import 'package:youmuz/src/ui/tokens.dart';

/// Cover art (`object-cover` with rounded corners). Loads through the Rust
/// image cache; placeholder and error state are a flat `bg-secondary` tile.
class GCover extends StatelessWidget {
  const GCover({
    required this.url,
    super.key,
    this.size,
    this.width,
    this.height,
    this.radius = GRadius.lg,
    this.icon = LucideIcons.music2,
    this.circle = false,
  });

  final String? url;
  final double? size;
  final double? width;
  final double? height;
  final double radius;
  final IconData icon;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final w = size ?? width;
    final h = size ?? height;
    final r = circle ? 9999.0 : radius;
    final placeholder = _CoverPlaceholder(width: w, height: h, icon: icon);

    Widget child;
    if (url == null || url!.isEmpty) {
      child = placeholder;
    } else {
      child = RustCachedImage(
        imageUrl: url,
        width: w,
        height: h,
        placeholder: placeholder,
        errorWidget: placeholder,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(width: w, height: h, child: child),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.icon, this.width, this.height});

  final double? width;
  final double? height;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = [
          width ?? constraints.maxWidth,
          height ?? constraints.maxHeight,
        ].where((v) => v.isFinite).fold<double>(48, (a, b) => a < b ? a : b);
        return Container(
          width: width,
          height: height,
          color: GColors.secondary,
          alignment: Alignment.center,
          child: Icon(icon, size: (side * 0.36).clamp(12, 64), color: GColors.mutedForeground),
        );
      },
    );
  }
}
