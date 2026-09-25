import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/features/core/views/widgets/rust_cached_image.dart';
import 'package:youmuz/src/ui/tokens.dart';

/// Initials of up to two words ("Анна Котова" -> "АК").
String initialsOf(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'[\s._-]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  final first = parts.first.characters.first;
  final second = parts.length > 1 ? parts[1].characters.first : '';
  return (first + second).toUpperCase();
}

/// Profile avatar: photo when available, otherwise initials on `bg-accent`
/// (`size-8 rounded-full text-xs font-medium`).
class GAvatar extends StatelessWidget {
  const GAvatar({
    required this.name,
    super.key,
    this.url,
    this.size = 32,
    this.ring = false,
  });

  final String name;
  final String? url;
  final double size;

  /// Amber ring marking the active account.
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final initials = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: GColors.accent,
      child: Text(
        initialsOf(name),
        style: GText.style(
          size <= 32 ? 12 : size * 0.36,
          weight: GText.medium,
        ),
      ),
    );
    final photo = url == null || url!.isEmpty
        ? initials
        : RustCachedImage(
            imageUrl: url,
            width: size,
            height: size,
            placeholder: initials,
            errorWidget: initials,
          );
    final avatar = ClipOval(child: SizedBox.square(dimension: size, child: photo));
    if (!ring) return avatar;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        border: Border.fromBorderSide(BorderSide(color: GColors.brand, width: 1.5)),
      ),
      child: avatar,
    );
  }
}
