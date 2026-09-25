import 'dart:async';
import 'dart:io';

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

/// Desktop player (`rounded-2xl bg-card px-4 py-2.5 gap-6`): track, transport,
/// waveform seek bar, then like / queue and the remaining controls.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final roomy = width >= 1180;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: GColors.card,
          borderRadius: BorderRadius.circular(GRadius.x2l),
        ),
        child: Row(
          children: [
            SizedBox(width: roomy ? 256 : 208, child: const _NowPlaying()),
            const SizedBox(width: 24),
            const _Transport(),
            const SizedBox(width: 24),
            const Expanded(child: _SeekBar()),
            const SizedBox(width: 24),
            _Extras(roomy: roomy),
          ],
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final meta = trackMetadataSignal();
        final hasTrack = meta.id != null;
        final albumId = meta.albumId;
        void openAlbum() {
          if (albumId != null && albumId.isNotEmpty) navigateTo(AppSection.album, albumId);
        }

        return Row(
          children: [
            GPressable(
              onTap: hasTrack ? openAlbum : null,
              focusable: false,
              builder: (context, s) => AnimatedOpacity(
                duration: GDurations.fast,
                opacity: s.hovered ? 0.8 : 1,
                child: GCover(url: meta.coverUrl, size: 44),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GPressable(
                    onTap: hasTrack ? openAlbum : null,
                    focusable: false,
                    builder: (context, s) => Text(
                      hasTrack
                          ? ((meta.version?.isNotEmpty ?? false) ? '${meta.title} (${meta.version})' : meta.title)
                          : 'Ничего не играет',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GText.sm(
                        weight: GText.medium,
                        color: hasTrack ? GColors.foreground : GColors.mutedForeground,
                      ).copyWith(decoration: s.hovered ? TextDecoration.underline : null),
                    ),
                  ),
                  if (hasTrack)
                    ArtistLinks(artists: meta.artists)
                  else
                    Text(
                      'Выберите трек или запустите волну',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GText.xs(color: GColors.mutedForeground),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final hasTrack = currentTrackIdSignal() != null;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GIconButton(
              glyph: GGlyphKind.skipBack,
              tooltip: 'Предыдущий трек',
              onPressed: hasTrack ? () => unawaited(PlaybackController.prev()) : null,
            ),
            const SizedBox(width: 4),
            GPlayButton(
              isPlaying: isPlayingSignal(),
              loading: showBufferingIndicatorSignal(),
              onPressed: hasTrack ? () => unawaited(PlaybackController.togglePlay()) : null,
            ),
            const SizedBox(width: 4),
            GIconButton(
              glyph: GGlyphKind.skipForward,
              tooltip: 'Следующий трек',
              onPressed: hasTrack ? () => unawaited(PlaybackController.next()) : null,
            ),
          ],
        );
      },
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final id = currentTrackIdSignal();
        final p = trackProgressSignal();
        final duration = id == null ? 0.0 : p.durationMs;
        final position = id == null ? 0.0 : p.positionMs;
        final ratio = duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;
        return Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                formatDuration(position.round()),
                textAlign: TextAlign.right,
                style: GText.time(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GWaveform(
                seed: id ?? 'idle',
                progress: ratio,
                onSeek: id == null || duration <= 1
                    ? null
                    : (r) => unawaited(
                        PlaybackController.seekTo(Duration(milliseconds: (r * duration).round())),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 40,
              child: Text(formatDuration(duration <= 1 ? 0 : duration.round()), style: GText.time()),
            ),
          ],
        );
      },
    );
  }
}

class _Extras extends StatelessWidget {
  const _Extras({required this.roomy});

  final bool roomy;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final trackId = currentTrackIdSignal();
        final hasTrack = trackId != null;
        final repeat = repeatModeSignal();
        final lyricsOn = showLyricsSignal();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GIconButton(
              glyph: GGlyphKind.heart,
              active: isLikedSignal(),
              tooltip: isLikedSignal() ? 'Убрать из понравившихся' : 'Нравится',
              onPressed: hasTrack ? () => unawaited(PlaybackController.toggleLike(trackId: trackId)) : null,
            ),
            GIconButton(
              icon: LucideIcons.ban,
              active: isDislikedSignal(),
              tooltip: 'Не рекомендовать',
              onPressed: hasTrack ? () => unawaited(PlaybackController.toggleDislike(trackId: trackId)) : null,
            ),
            GIconButton(
              icon: LucideIcons.shuffle,
              active: isShuffledSignal(),
              tooltip: 'Перемешать',
              onPressed: () => unawaited(PlaybackController.toggleShuffle()),
            ),
            GIconButton(
              icon: repeat == RepeatModeDto.single ? LucideIcons.repeat1 : LucideIcons.repeat,
              active: repeat != RepeatModeDto.none,
              tooltip: switch (repeat) {
                RepeatModeDto.none => 'Повтор выключен',
                RepeatModeDto.all => 'Повторять очередь',
                RepeatModeDto.single => 'Повторять трек',
              },
              onPressed: () => unawaited(PlaybackController.toggleRepeat()),
            ),
            GIconButton(
              icon: LucideIcons.micVocal,
              active: lyricsOn,
              tooltip: 'Текст песни',
              onPressed: hasTrack ? () => showLyricsSignal.value = !lyricsOn : null,
            ),
            GIconButton(
              icon: LucideIcons.listMusic,
              tooltip: 'Очередь',
              onPressed: () => unawaited(showQueuePanel(context)),
            ),
            if (!Platform.isAndroid) ...[
              const SizedBox(width: 4),
              _Volume(width: roomy ? 96 : 64),
            ],
            const SizedBox(width: 4),
            const CommonQualitySelector(),
          ],
        );
      },
    );
  }
}

/// Volume icon (click mutes/restores) and a thin slider.
class _Volume extends StatefulWidget {
  const _Volume({required this.width});

  final double width;

  @override
  State<_Volume> createState() => _VolumeState();
}

class _VolumeState extends State<_Volume> {
  double? _drag;
  int _beforeMute = 70;

  void _set(int v) {
    unawaited(PlaybackController.changeVolume(v));
    unawaited(PlaybackController.commitVolume());
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final volume = playerVolumeSignal();
        final shown = _drag ?? volume.toDouble();
        final muted = shown <= 0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GIconButton(
              icon: muted ? LucideIcons.volumeX : LucideIcons.volume2,
              tooltip: muted ? 'Включить звук' : 'Выключить звук',
              onPressed: () {
                if (muted) {
                  _set(_beforeMute <= 0 ? 70 : _beforeMute);
                } else {
                  _beforeMute = volume;
                  _set(0);
                }
              },
            ),
            SizedBox(
              width: widget.width,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5, elevation: 0, pressedElevation: 0),
                  trackHeight: 3,
                ),
                child: Slider(
                  value: shown.clamp(0, 100),
                  max: 100,
                  semanticFormatterCallback: (v) => 'Громкость ${v.round()}%',
                  onChanged: (v) {
                    setState(() => _drag = v);
                    unawaited(PlaybackController.changeVolume(v.round()));
                  },
                  onChangeEnd: (_) {
                    setState(() => _drag = null);
                    unawaited(PlaybackController.commitVolume());
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
