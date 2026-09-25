import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/core/views/widgets/track_actions.dart';
import 'package:youmuz/src/features/playback/providers/playback_provider.dart';
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Play queue: the current track highlighted, upcoming tracks below.
Future<void> showQueuePanel(BuildContext context) {
  return showGDialog<void>(
    context,
    builder: (context) => GDialog(
      title: 'Очередь',
      width: 520,
      padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
      content: SignalBuilder(
        builder: (context) {
          final queue = queueTracksSignal().value ?? const <SimpleTrackDto>[];
          final index = playerStateSignal()?.queueIndex ?? 0;
          final playing = isPlayingSignal();
          if (queue.isEmpty) {
            return const GEmptyState(
              icon: LucideIcons.listMusic,
              title: 'Очередь пуста',
              message: 'Запустите альбом, плейлист или Мою волну.',
              compact: true,
            );
          }
          return ListView.builder(
            shrinkWrap: true,
            itemCount: queue.length,
            itemBuilder: (context, i) {
              final t = queue[i];
              final isCurrent = i == index;
              return Opacity(
                opacity: i < index ? 0.5 : 1,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 2, right: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isCurrent ? GColors.secondary : const Color(0x00000000),
                    borderRadius: BorderRadius.circular(GRadius.xl),
                  ),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 40,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            GCover(url: t.coverUrl, size: 40, radius: GRadius.md),
                            if (isCurrent)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: GColors.coverOverlay,
                                  borderRadius: BorderRadius.circular(GRadius.md),
                                ),
                                child: Center(child: GEqualizer(playing: playing)),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trackTitle(t),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GText.sm(
                                weight: GText.medium,
                                color: isCurrent ? GColors.brand : GColors.foreground,
                              ),
                            ),
                            Text(
                              artistNames(t.artists),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GText.xs(color: GColors.mutedForeground),
                            ),
                          ],
                        ),
                      ),
                      Text(formatDuration(t.durationMs), style: GText.time(size: 12)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}
