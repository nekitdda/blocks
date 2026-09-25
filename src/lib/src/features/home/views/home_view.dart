import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/auth/providers/auth_provider.dart';
import 'package:youmuz/src/features/core/providers/navigation_provider.dart';
import 'package:youmuz/src/features/core/services/rust_bridge.dart';
import 'package:youmuz/src/features/core/views/widgets/media_tile.dart';
import 'package:youmuz/src/features/core/views/widgets/track_actions.dart';
import 'package:youmuz/src/features/core/views/widgets/track_row.dart';
import 'package:youmuz/src/features/library/providers/library_provider.dart';
import 'package:youmuz/src/features/playback/providers/playback_provider.dart';
import 'package:youmuz/src/features/playback/providers/wave_provider.dart';
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/rust/api/playback.dart' as rust_playback;
import 'package:youmuz/src/ui/ui.dart';

String greeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 5) return 'Доброй ночи';
  if (h < 12) return 'Доброе утро';
  if (h < 18) return 'Добрый день';
  return 'Добрый вечер';
}

/// Recently played tracks of the active account (persisted per account).
final FlutterSignal<List<SimpleTrackDto>> recentTracksSignal = signal(const []);

Future<void> refreshRecentTracks() async {
  final tracks = await runRustFetch((ctx) => rust_playback.getHistory(ctx: ctx, limit: 12));
  if (tracks != null) recentTracksSignal.value = tracks;
}

/// Home: greeting, "Моя волна" card with the user's playlists, playlist
/// covers, recently played tracks and albums from the collection.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  EffectCleanup? _historySync;

  @override
  void initState() {
    super.initState();
    recentTracksSignal.value = const [];
    unawaited(refreshLikedTracks());
    unawaited(refreshLikedAlbums());
    // New entries land in the history once a track starts playing.
    _historySync = effect(() {
      currentTrackIdSignal();
      isPlayingSignal();
      Future<void>.delayed(const Duration(milliseconds: 800), refreshRecentTracks);
    });
  }

  @override
  void dispose() {
    _historySync?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= GLayout.wideBreakpoint;
        return GScrollPage(
          children: [
            SignalBuilder(
              builder: (context) {
                final account = accountSignal();
                final active = activeStoredAccountSignal();
                final name = _firstName(
                  account?.displayName ?? account?.fullName ?? active?.displayName ?? account?.login ?? '',
                );
                return Text(
                  name.isEmpty ? greeting() : '${greeting()}, $name',
                  style: GText.sm(color: GColors.mutedForeground),
                );
              },
            ),
            const SizedBox(height: 16),
            if (wide)
              const SizedBox(
                height: 264,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 14, child: _WaveHero()),
                    SizedBox(width: 12),
                    Expanded(flex: 10, child: _MyPlaylists()),
                  ],
                ),
              )
            else ...[
              const _WaveHero(),
              const SizedBox(height: 12),
              const SizedBox(height: 168, child: _MyPlaylists()),
            ],
            const SizedBox(height: 48),
            const _PlaylistShelf(),
            const SizedBox(height: 48),
            if (wide)
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _RecentTracks()),
                  SizedBox(width: 48),
                  Expanded(child: _CollectionAlbums()),
                ],
              )
            else ...[
              const _RecentTracks(),
              const SizedBox(height: 48),
              const _CollectionAlbums(),
            ],
          ],
        );
      },
    );
  }

  static String _firstName(String full) {
    final trimmed = full.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(RegExp(r'\s+')).first;
  }
}

class _WaveHero extends StatelessWidget {
  const _WaveHero();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final seeds = currentWaveSeedsSignal();
        final waveActive = seeds.isNotEmpty;
        final playing = isPlayingSignal() && waveActive;
        final meta = trackMetadataSignal();
        final p = trackProgressSignal();
        final ratio = waveActive && p.durationMs > 1 ? (p.positionMs / p.durationMs).clamp(0.0, 1.0) : 0.0;
        final artists = artistNames(meta.artists);
        final wide = MediaQuery.sizeOf(context).width >= GLayout.mediumBreakpoint;

        return Container(
          padding: EdgeInsets.all(wide ? 32 : 24),
          decoration: BoxDecoration(
            color: GColors.card,
            borderRadius: BorderRadius.circular(GRadius.x3l),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Моя волна', style: GText.headline(wide ? 36 : 30)),
                        const SizedBox(height: 8),
                        Text(
                          playing && meta.id != null
                              ? 'Сейчас: ${meta.title}${artists.isEmpty ? '' : ' — $artists'}'
                              : 'Персональный поток, который учится на ваших лайках',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GText.sm(color: GColors.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  GCircleButton(
                    icon: LucideIcons.arrowUpRight,
                    tooltip: 'Открыть «Мою волну»',
                    onPressed: () => navigateTo(AppSection.wave),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              Row(
                children: [
                  GPlayButton(
                    size: 56,
                    iconSize: 20,
                    isPlaying: playing,
                    onPressed: () => unawaited(
                      waveActive && meta.id != null
                          ? PlaybackController.togglePlay()
                          : WaveController.startMyWave(),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: GWaveform(
                      seed: waveActive ? (meta.id ?? 'wave') : 'wave',
                      count: 64,
                      height: 48,
                      progress: ratio,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MyPlaylists extends StatelessWidget {
  const _MyPlaylists();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final liked = likedTracksSignal();
        final playlists = playlistsSignal().where((p) => p.kind != 3).take(3).toList();
        final tiles = <Widget>[
          CompactMediaTile(
            title: 'Мне нравится',
            subtitle: liked.isEmpty ? 'Ваши лайки' : '${liked.length} ${plural(liked.length, 'трек', 'трека', 'треков')}',
            cover: const LikedCover(size: 56, radius: GRadius.xl),
            onTap: () => navigateTo(AppSection.liked),
          ),
          for (final p in playlists)
            CompactMediaTile(
              title: p.title,
              subtitle: '${p.trackCount} ${plural(p.trackCount, 'трек', 'трека', 'треков')}',
              coverUrl: p.coverUrl,
              onTap: () => navigateTo(AppSection.playlist, '${p.uid}:${p.kind}'),
            ),
          if (playlists.length < 3)
            CompactMediaTile(
              title: 'Все плейлисты',
              subtitle: 'Коллекция',
              cover: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: GColors.accent,
                  borderRadius: BorderRadius.circular(GRadius.xl),
                ),
                child: const Icon(LucideIcons.library, size: 20, color: GColors.mutedForeground),
              ),
              onTap: () => navigateTo(AppSection.playlists),
            ),
        ];
        // Two columns like the reference; with two tiles or fewer they
        // stack so they do not stretch into tall empty cards.
        final perRow = tiles.length <= 2 ? 1 : 2;
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += perRow) {
          rows.add(
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tiles[i]),
                  if (perRow == 2) ...[
                    const SizedBox(width: 12),
                    Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
                  ],
                ],
              ),
            ),
          );
          if (i + perRow < tiles.length) rows.add(const SizedBox(height: 12));
        }
        return Column(children: rows);
      },
    );
  }
}

class _PlaylistShelf extends StatelessWidget {
  const _PlaylistShelf();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final playlists = playlistsSignal();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GSectionHeader(
              'Ваши плейлисты',
              trailing: GTextAction(label: 'Все', onPressed: () => navigateTo(AppSection.playlists)),
            ),
            if (playlists.isEmpty)
              Text('Плейлистов пока нет.', style: GText.sm(color: GColors.mutedForeground))
            else
              MediaGrid(
                children: [
                  for (final p in playlists.take(6))
                    MediaTile(
                      title: p.title,
                      subtitle: '${p.trackCount} ${plural(p.trackCount, 'трек', 'трека', 'треков')}',
                      coverUrl: p.coverUrl,
                      icon: LucideIcons.listMusic,
                      onTap: () => navigateTo(AppSection.playlist, '${p.uid}:${p.kind}'),
                      menu: () => [
                        GMenuItem(
                          label: 'Слушать',
                          icon: LucideIcons.play,
                          onSelected: () => unawaited(PlaybackController.playPlaylist('${p.uid}', p.kind)),
                        ),
                      ],
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _RecentTracks extends StatelessWidget {
  const _RecentTracks();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final recent = recentTracksSignal().take(5).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const GSectionHeader('Недавно слушали', bottom: 12),
            if (recent.isEmpty)
              Text(
                'Здесь появятся треки, которые вы слушали в этом аккаунте.',
                style: GText.sm(color: GColors.mutedForeground),
              )
            else
              for (final t in recent)
                TrackRow(
                  track: t,
                  showAlbum: false,
                  onPlay: () => unawaited(PlaybackController.playTrack(t.id)),
                ),
          ],
        );
      },
    );
  }
}

class _CollectionAlbums extends StatelessWidget {
  const _CollectionAlbums();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final albums = likedAlbumsSignal().take(4).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GSectionHeader(
              'Альбомы в коллекции',
              trailing: albums.isEmpty
                  ? null
                  : GTextAction(label: 'Все', onPressed: () => navigateTo(AppSection.liked)),
            ),
            if (albums.isEmpty)
              Text('Добавьте альбомы в коллекцию — они появятся здесь.', style: GText.sm(color: GColors.mutedForeground))
            else
              LayoutBuilder(
                builder: (context, c) {
                  final tileWidth = (c.maxWidth - 16) / 2;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final a in albums)
                        SizedBox(
                          width: tileWidth,
                          child: CompactMediaTile(
                            card: false,
                            coverSize: MediaQuery.sizeOf(context).width >= GLayout.mediumBreakpoint ? 72 : 64,
                            title: a.title,
                            subtitle: [
                              artistNames(a.artists),
                              if (a.year != null) '${a.year}',
                            ].where((s) => s.isNotEmpty).join(' · '),
                            coverUrl: a.coverUrl,
                            onTap: () => navigateTo(AppSection.album, a.id),
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
