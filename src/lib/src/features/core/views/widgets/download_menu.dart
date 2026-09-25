import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/ui/ui.dart';

enum DownloadMode { cache, files }

/// "Скачать" trigger with a menu of download targets: the app cache (offline
/// playback) or separate audio files. [compact] renders a round icon button,
/// otherwise a secondary pill with a label.
class DownloadTargetMenu extends StatelessWidget {
  final bool compact;
  final bool isLoading;
  final void Function(DownloadMode mode) onSelected;
  final bool enabled;

  /// Diameter of the [compact] button.
  final double size;

  const DownloadTargetMenu({
    required this.compact,
    required this.isLoading,
    required this.onSelected,
    this.enabled = true,
    this.size = 40,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = enabled && !isLoading;

    return GMenu(
      items: () => [
        GMenuItem(
          label: 'В кэш приложения',
          icon: LucideIcons.hardDriveDownload,
          onSelected: () => onSelected(DownloadMode.cache),
        ),
        GMenuItem(
          label: 'В отдельные файлы',
          icon: LucideIcons.fileDown,
          onSelected: () => onSelected(DownloadMode.files),
        ),
      ],
      builder: (context, menu) {
        final open = isEnabled ? () => menu.open() : null;
        if (!compact) {
          return GButton(
            label: 'Скачать',
            icon: LucideIcons.download,
            variant: GButtonVariant.secondary,
            loading: isLoading,
            onPressed: open,
          );
        }
        if (isLoading) return _DownloadingCircle(size: size);
        return GCircleButton(
          icon: LucideIcons.download,
          tooltip: 'Скачать',
          size: size,
          iconSize: size >= 48 ? 20 : 16,
          onPressed: open,
        );
      },
    );
  }
}

/// [GCircleButton] footprint with a spinner while a download is running.
class _DownloadingCircle extends StatelessWidget {
  final double size;

  const _DownloadingCircle({required this.size});

  @override
  Widget build(BuildContext context) {
    final spinner = size >= 48 ? 20.0 : 16.0;
    return Tooltip(
      message: 'Скачивание…',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: GColors.secondary,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(
          dimension: spinner,
          child: const CircularProgressIndicator(
            strokeWidth: 1.8,
            color: GColors.mutedForeground,
          ),
        ),
      ),
    );
  }
}
