import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/core/providers/navigation_provider.dart';
import 'package:youmuz/src/features/core/views/layout/queue_panel.dart';
import 'package:youmuz/src/features/core/views/widgets/quality_selector.dart';
import 'package:youmuz/src/features/core/views/widgets/track_actions.dart';
import 'package:youmuz/src/features/core/views/widgets/track_row.dart';
import 'package:youmuz/src/features/playback/providers/playback_provider.dart';
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Compact player for the touch layout: swipe left/right to skip, tap to
/// open the full player.
class MobileMiniPlayer extends StatefulWidget {
  const MobileMiniPlayer({super.key});

  @override
  State<MobileMiniPlayer> createState() => _MobileMiniPlayerState();
}

class _MobileMiniPlayerState extends State<MobileMiniPlayer> {
  double _dragDx = 0;

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_dragDx < -60 || v < -600) {
      unawaited(PlaybackController.next());
    } else if (_dragDx > 60 || v > 600) {
      unawaited(PlaybackController.prev());
    }
    setState(() => _dragDx = 0);
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final meta = trackMetadataSignal();
        if (meta.id == null) return const SizedBox.shrink();
        final p = trackProgressSignal();
        final ratio = p.durationMs > 1 ? (p.positionMs / p.durationMs).clamp(0.0, 1.0) : 0.0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: GestureDetector(
            onTap: () => unawaited(showFullPlayer(context)),
            onHorizontalDragUpdate: (d) => setState(() => _dragDx += d.delta.dx),
            onHorizontalDragEnd: _onDragEnd,
            child: Container(
              decoration: BoxDecoration(
                color: GColors.card,
                borderRadius: BorderRadius.circular(GRadius.x2l),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                    child: Row(
                      children: [
                        Transform.translate(
                          offset: Offset(_dragDx.clamp(-40, 40) * 0.5, 0),
                          child: GCover(url: meta.coverUrl, size: 44),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                meta.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GText.sm(weight: GText.medium),
                              ),
                              Text(
                                artistNames(meta.artists),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GText.xs(color: GColors.mutedForeground),
                              ),
                            ],
                          ),
                        ),
                        GIconButton(
                          glyph: GGlyphKind.heart,
                          active: isLikedSignal(),
                          onPressed: () => unawaited(PlaybackController.toggleLike(trackId: meta.id!)),
                        ),
                        GPlayButton(
                          isPlaying: isPlayingSignal(),
                          loading: showBufferingIndicatorSignal(),
                          size: 36,
                          iconSize: 14,
                          onPressed: () => unawaited(PlaybackController.togglePlay()),
                        ),
                        GIconButton(
                          glyph: GGlyphKind.skipForward,
                          onPressed: () => unawaited(PlaybackController.next()),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 2,
                    child: LinearProgressIndicator(
                      value: ratio,
                      color: GColors.foreground,
                      backgroundColor: GColors.foreground20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Full-screen player sheet for the touch layout.
Future<void> showFullPlayer(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: GColors.background,
    builder: (context) => const _FullPlayer(),
  );
}

class _FullPlayer extends StatelessWidget {
  const _FullPlayer();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final meta = trackMetadataSignal();
        final id = meta.id;
        final p = trackProgressSignal();
        final duration = p.durationMs;
        final ratio = duration > 1 ? (p.positionMs / duration).clamp(0.0, 1.0) : 0.0;
        final repeat = repeatModeSignal();
        final size = MediaQuery.sizeOf(context);
        final cover = (size.width - 48).clamp(160.0, size.height * 0.42);

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GPressable(
                  onTap: meta.albumId == null
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          navigateTo(AppSection.album, meta.albumId);
                        },
                  focusable: false,
                  builder: (context, s) => GCover(url: meta.coverUrl, size: cover, radius: GRadius.x3l),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                meta.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GText.headline(26),
              ),
              const SizedBox(height: 6),
              ArtistLinks(artists: meta.artists, style: GText.base(color: GColors.mutedForeground)),
              const SizedBox(height: 24),
              GWaveform(
                seed: id ?? 'idle',
                count: 56,
                height: 44,
                progress: ratio,
                onSeek: id == null || duration <= 1
                    ? null
                    : (r) => unawaited(
                        PlaybackController.seekTo(Duration(milliseconds: (r * duration).round())),
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatDuration(p.positionMs.round()), style: GText.time(size: 12)),
                  Text(formatDuration(duration <= 1 ? 0 : duration.round()), style: GText.time(size: 12)),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GIconButton(
                    icon: LucideIcons.shuffle,
                    size: 20,
                    active: isShuffledSignal(),
                    onPressed: () => unawaited(PlaybackController.toggleShuffle()),
                  ),
                  GCircleButton(
                    glyph: GGlyphKind.skipBack,
                    size: 52,
                    iconSize: 20,
                    variant: GCircleVariant.strong,
                    onPressed: () => unawaited(PlaybackController.prev()),
                  ),
                  GPlayButton(
                    isPlaying: isPlayingSignal(),
                    loading: showBufferingIndicatorSignal(),
                    size: 68,
                    iconSize: 24,
                    onPressed: () => unawaited(PlaybackController.togglePlay()),
                  ),
                  GCircleButton(
                    glyph: GGlyphKind.skipForward,
                    size: 52,
                    iconSize: 20,
                    variant: GCircleVariant.strong,
                    onPressed: () => unawaited(PlaybackController.next()),
                  ),
                  GIconButton(
                    icon: repeat == RepeatModeDto.single ? LucideIcons.repeat1 : LucideIcons.repeat,
                    size: 20,
                    active: repeat != RepeatModeDto.none,
                    onPressed: () => unawaited(PlaybackController.toggleRepeat()),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  GIconButton(
                    glyph: GGlyphKind.heart,
                    size: 20,
                    active: isLikedSignal(),
                    onPressed: id == null ? null : () => unawaited(PlaybackController.toggleLike(trackId: id)),
                  ),
                  GIconButton(
                    icon: LucideIcons.ban,
                    size: 20,
                    active: isDislikedSignal(),
                    onPressed: id == null ? null : () => unawaited(PlaybackController.toggleDislike(trackId: id)),
                  ),
                  GIconButton(
                    icon: LucideIcons.micVocal,
                    size: 20,
                    active: showLyricsSignal(),
                    onPressed: () {
                      showLyricsSignal.value = !showLyricsSignal.value;
                      Navigator.of(context).pop();
                    },
                  ),
                  GIconButton(
                    icon: LucideIcons.listMusic,
                    size: 20,
                    onPressed: () => unawaited(showQueuePanel(context)),
                  ),
                  const CommonQualitySelector(),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MobileTab {
  const _MobileTab(this.section, this.label, this.icon);
  final AppSection section;
  final String label;
  final IconData icon;
}

const _tabs = [
  _MobileTab(AppSection.home, 'Главная', LucideIcons.house),
  _MobileTab(AppSection.wave, 'Волна', LucideIcons.audioLines),
  _MobileTab(AppSection.liked, 'Коллекция', LucideIcons.library),
  _MobileTab(AppSection.search, 'Поиск', LucideIcons.search),
];

/// Bottom navigation for the touch layout.
class MobileNavBar extends StatelessWidget {
  const MobileNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final root = currentRootSignal();
        return Container(
          decoration: const BoxDecoration(
            color: GColors.background,
            border: Border(top: BorderSide(color: GColors.border)),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          height: 60 + MediaQuery.paddingOf(context).bottom,
          child: Row(
            children: [
              for (final tab in _tabs)
                Expanded(
                  child: GPressable(
                    onTap: () => navigateTo(tab.section),
                    semanticLabel: tab.label,
                    selected: root == tab.section,
                    builder: (context, s) {
                      final active = root == tab.section;
                      final color = active ? GColors.foreground : GColors.mutedForeground;
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: GDurations.fast,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: active ? GColors.secondary : const Color(0x00000000),
                              borderRadius: BorderRadius.circular(GRadius.full),
                            ),
                            child: Icon(tab.icon, size: 18, color: color),
                          ),
                          const SizedBox(height: 4),
                          Text(tab.label, style: GText.style(11, lineHeight: 14, color: color)),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
