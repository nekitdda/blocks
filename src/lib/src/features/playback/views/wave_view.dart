import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/core/views/widgets/track_actions.dart';
import 'package:youmuz/src/features/core/views/widgets/track_row.dart';
import 'package:youmuz/src/features/playback/providers/playback_provider.dart';
import 'package:youmuz/src/features/playback/providers/wave_provider.dart';
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Wave setting presets (Rotor seeds).
class WaveOption {
  const WaveOption(this.label, this.seed);
  final String label;
  final String seed;
}

class WaveGroup {
  const WaveGroup(this.label, this.options);
  final String label;
  final List<WaveOption> options;
}

const waveGroups = [
  WaveGroup('Занятие', [
    WaveOption('Просыпаюсь', 'activity:wake-up'),
    WaveOption('Работаю', 'activity:work-background'),
    WaveOption('В дороге', 'activity:road-trip'),
    WaveOption('Тренируюсь', 'activity:workout'),
    WaveOption('Засыпаю', 'activity:fall-asleep'),
  ]),
  WaveGroup('Характер', [
    WaveOption('Любимое', 'personal:collection'),
    WaveOption('Незнакомое', 'personal:never-heard'),
    WaveOption('Популярное', 'personal:hits'),
  ]),
  WaveGroup('Настроение', [
    WaveOption('Бодрое', 'mood:energetic'),
    WaveOption('Весёлое', 'mood:happy'),
    WaveOption('Спокойное', 'mood:calm'),
    WaveOption('Грустное', 'mood:sad'),
  ]),
  WaveGroup('Язык', [
    WaveOption('Русский', 'local-language:russian'),
    WaveOption('Иностранный', 'local-language:english'),
    WaveOption('Без слов', 'local-language:instrumental'),
  ]),
];

const _defaultSeed = 'user:onyourwave';

/// Human label for a seed ("activity:workout" -> "Тренируюсь").
String waveSeedLabel(String seed, List<StationCategoryDto> stations) {
  for (final g in waveGroups) {
    for (final o in g.options) {
      if (o.seed == seed) return o.label;
    }
  }
  for (final c in stations) {
    for (final i in c.items) {
      if (i.seed == seed) return i.label;
    }
  }
  if (seed.startsWith('track:')) {
    final first = seed.indexOf(':');
    final second = seed.indexOf(':', first + 1);
    return second > 0 ? 'По треку «${seed.substring(second + 1)}»' : 'По треку';
  }
  if (seed.startsWith('artist:')) return 'По исполнителю';
  return seed;
}

bool _isWaveActive(List<String> seeds) => seeds.isNotEmpty;

/// "Моя волна": large now-playing block with a waveform seek bar and the
/// wave settings in a side column.
class WaveView extends StatelessWidget {
  const WaveView({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= GLayout.wideBreakpoint;
        final padding = GLayout.pagePadding(width);
        final main = const _WaveMain();
        const aside = _WaveAside();
        return Scrollbar(
          child: SingleChildScrollView(
            primary: true,
            child: GPageFrame(
              padding: EdgeInsets.fromLTRB(padding.left, wide ? 48 : 32, padding.right, 48),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: main),
                        const SizedBox(width: 40),
                        Container(
                          width: 320 + 33,
                          padding: const EdgeInsets.only(left: 32),
                          decoration: const BoxDecoration(
                            border: Border(left: BorderSide(color: GColors.border)),
                          ),
                          child: aside,
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [main, const SizedBox(height: 40), aside],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveMain extends StatelessWidget {
  const _WaveMain();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final seeds = currentWaveSeedsSignal();
        final waveActive = _isWaveActive(seeds);
        final playing = isPlayingSignal();
        final meta = trackMetadataSignal();
        final hasTrack = meta.id != null;
        final stations = waveStationsSignal().value ?? const <StationCategoryDto>[];
        final width = MediaQuery.sizeOf(context).width;
        final titleSize = width >= 1280 ? 96.0 : (width >= 768 ? 72.0 : 48.0);
        final p = trackProgressSignal();
        final duration = hasTrack ? p.durationMs : 0.0;
        final ratio = duration > 1 ? (p.positionMs / duration).clamp(0.0, 1.0) : 0.0;
        final activeLabels = seeds
            .where((s) => s != _defaultSeed)
            .map((s) => waveSeedLabel(s, stations))
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: GDurations.fast,
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: playing && waveActive ? GColors.brand : GColors.mutedForeground,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(header: true, child: Text('Моя волна', style: GText.sm(color: GColors.mutedForeground))),
                const SizedBox(width: 8),
                Text('·', style: GText.sm(color: GColors.mutedForeground)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    activeLabels.isEmpty
                        ? (waveActive ? 'Персональный поток' : 'Не запущена')
                        : activeLabels.join(', ').toLowerCase().replaceFirstMapped(
                            RegExp('^.'),
                            (m) => m[0]!.toUpperCase(),
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GText.sm(color: GColors.mutedForeground),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            if (hasTrack && waveActive)
              _NowPlayingHero(meta: meta, titleSize: titleSize)
            else
              _IdleHero(titleSize: titleSize),
            const SizedBox(height: 48),
            GWaveform(
              seed: meta.id ?? 'wave',
              count: 120,
              height: 80,
              progress: hasTrack && waveActive ? ratio : 0,
              onSeek: hasTrack && waveActive && duration > 1
                  ? (r) => unawaited(PlaybackController.seekTo(Duration(milliseconds: (r * duration).round())))
                  : null,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDuration(hasTrack && waveActive ? p.positionMs.round() : 0), style: GText.time(size: 12)),
                Text(formatDuration(hasTrack && waveActive && duration > 1 ? duration.round() : 0), style: GText.time(size: 12)),
              ],
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                GPlayButton(
                  size: 64,
                  iconSize: 24,
                  isPlaying: playing && waveActive,
                  loading: waveActive && showBufferingIndicatorSignal(),
                  onPressed: () => unawaited(
                    waveActive && hasTrack ? PlaybackController.togglePlay() : WaveController.startMyWave(),
                  ),
                ),
                const SizedBox(width: 12),
                GCircleButton(
                  glyph: GGlyphKind.skipForward,
                  size: 48,
                  iconSize: 20,
                  variant: GCircleVariant.strong,
                  tooltip: 'Следующий трек',
                  onPressed: waveActive && hasTrack ? () => unawaited(PlaybackController.next()) : null,
                ),
                const SizedBox(width: 12),
                GCircleButton(
                  glyph: GGlyphKind.heart,
                  size: 48,
                  iconSize: 20,
                  variant: GCircleVariant.strong,
                  active: isLikedSignal(),
                  tooltip: 'Нравится',
                  onPressed: hasTrack ? () => unawaited(PlaybackController.toggleLike(trackId: meta.id!)) : null,
                ),
                const SizedBox(width: 12),
                GCircleButton(
                  icon: LucideIcons.ban,
                  size: 48,
                  iconSize: 20,
                  tooltip: 'Не рекомендовать',
                  active: isDislikedSignal(),
                  onPressed: hasTrack
                      ? () => unawaited(PlaybackController.toggleDislike(trackId: meta.id!))
                      : null,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _NowPlayingHero extends StatelessWidget {
  const _NowPlayingHero({required this.meta, required this.titleSize});

  final ({
    String? id,
    String title,
    String? version,
    List<TrackArtistDto> artists,
    String? coverUrl,
    String? albumId,
    String? codec,
  }) meta;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 768;
    final cover = GCover(url: meta.coverUrl, size: narrow ? 160 : 224, radius: GRadius.xl);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(meta.title, style: GText.display(titleSize), maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 16),
        ArtistLinks(artists: meta.artists, style: GText.lg(color: GColors.mutedForeground)),
      ],
    );
    return Semantics(
      liveRegion: true,
      child: narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [cover, const SizedBox(height: 32), text])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [cover, const SizedBox(width: 32), Expanded(child: text)],
            ),
    );
  }
}

class _IdleHero extends StatelessWidget {
  const _IdleHero({required this.titleSize});

  final double titleSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Моя волна', style: GText.display(titleSize)),
        const SizedBox(height: 16),
        Text(
          'Персональный поток, который учится на ваших лайках. Выберите настроение справа или просто нажмите «Играть».',
          style: GText.lg(color: GColors.mutedForeground),
        ),
      ],
    );
  }
}

class _WaveAside extends StatelessWidget {
  const _WaveAside();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final seeds = currentWaveSeedsSignal();
        final queue = queueTracksSignal().value ?? const <SimpleTrackDto>[];
        final index = playerStateSignal()?.queueIndex ?? 0;
        final upcoming = _isWaveActive(seeds)
            ? queue.skip(index + 1).take(3).toList()
            : const <SimpleTrackDto>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Настройки волны', style: GText.sm(weight: GText.medium))),
                if (seeds.any((s) => s != _defaultSeed))
                  GTextAction(
                    label: 'Сбросить',
                    style: GText.xs(),
                    onPressed: () => unawaited(WaveController.resetStations()),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            for (final group in waveGroups) ...[
              Text(group.label, style: GText.xs(color: GColors.mutedForeground)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final o in group.options)
                    GChip(
                      label: o.label,
                      active: seeds.contains(o.seed),
                      onPressed: () => unawaited(WaveController.toggleStation(o.seed)),
                    ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            GButton(
              label: 'Все станции',
              icon: LucideIcons.radio,
              variant: GButtonVariant.secondary,
              size: GButtonSize.sm,
              onPressed: () => unawaited(_showAllStations(context)),
            ),
            const SizedBox(height: 32),
            Text('Дальше в волне', style: GText.sm(weight: GText.medium)),
            const SizedBox(height: 16),
            if (upcoming.isEmpty)
              Text(
                'Появится, когда волна заиграет.',
                style: GText.xs(color: GColors.mutedForeground),
              )
            else
              for (final t in upcoming)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Opacity(
                    opacity: 0.8,
                    child: Row(
                      children: [
                        GCover(url: t.coverUrl, size: 40, radius: GRadius.md),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(trackTitle(t), maxLines: 1, overflow: TextOverflow.ellipsis, style: GText.sm()),
                              Text(
                                artistNames(t.artists),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GText.xs(color: GColors.mutedForeground),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

Future<void> _showAllStations(BuildContext context) {
  return showGDialog<void>(
    context,
    builder: (context) => GDialog(
      title: 'Все станции',
      description: 'Станция заменит текущие настройки волны.',
      width: 640,
      content: SignalBuilder(
        builder: (context) {
          final async = waveStationsSignal();
          final cats = async.value ?? const <StationCategoryDto>[];
          final seeds = currentWaveSeedsSignal();
          if (cats.isEmpty) {
            return async.isLoading
                ? const GLoader()
                : GEmptyState(
                    icon: LucideIcons.radio,
                    title: 'Станции не загрузились',
                    action: GButton(
                      label: 'Повторить',
                      variant: GButtonVariant.secondary,
                      onPressed: () => unawaited(WaveController.refresh()),
                    ),
                    compact: true,
                  );
          }
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in cats) ...[
                  Text(c.title, style: GText.xs(color: GColors.mutedForeground)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final i in c.items)
                        GChip(
                          label: i.label,
                          active: seeds.contains(i.seed),
                          onPressed: () {
                            unawaited(WaveController.playStation(i.seed));
                            Navigator.of(context).pop();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          );
        },
      ),
    ),
  );
}
