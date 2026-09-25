import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/core/providers/navigation_provider.dart';
import 'package:youmuz/src/features/core/providers/notification_provider.dart';
import 'package:youmuz/src/features/core/views/widgets/download_menu.dart';
import 'package:youmuz/src/features/core/views/widgets/media_tile.dart';
import 'package:youmuz/src/features/core/views/widgets/track_actions.dart';
import 'package:youmuz/src/features/core/views/widgets/track_row.dart';
import 'package:youmuz/src/features/library/providers/library_provider.dart';
import 'package:youmuz/src/features/playback/providers/playback_provider.dart';
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/ui/ui.dart';

enum _Tab { tracks, playlists, albums, artists }

const _tabLabels = {
  _Tab.tracks: 'Мне нравится',
  _Tab.playlists: 'Плейлисты',
  _Tab.albums: 'Альбомы',
  _Tab.artists: 'Исполнители',
};

/// "Коллекция": liked tracks, playlists, albums and artists of the account.
class LibraryView extends StatefulWidget {
  const LibraryView({super.key});

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  _Tab _tab = _Tab.tracks;
  final _searchController = TextEditingController();
  EffectCleanup? _requestSync;
  final Set<_Tab> _loaded = {};

  @override
  void initState() {
    super.initState();
    _searchController.text = librarySearchQuerySignal.value;
    _requestSync = effect(() {
      final requested = librarySectionRequestSignal();
      final tab = requested == AppSection.playlists ? _Tab.playlists : _Tab.tracks;
      if (mounted && tab != _tab) setState(() => _tab = tab);
      _ensureLoaded(tab);
    });
  }

  void _ensureLoaded(_Tab tab) {
    if (!_loaded.add(tab)) return;
    switch (tab) {
      case _Tab.tracks:
        unawaited(refreshLikedTracks(query: librarySearchQuerySignal.value.isEmpty ? null : librarySearchQuerySignal.value));
      case _Tab.playlists:
        unawaited(refreshPlaylists());
      case _Tab.albums:
        unawaited(refreshLikedAlbums());
      case _Tab.artists:
        unawaited(refreshLikedArtists());
    }
  }

  void _select(_Tab tab) {
    setState(() => _tab = tab);
    _ensureLoaded(tab);
  }

  @override
  void dispose() {
    _requestSync?.call();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = GLayout.pagePadding(constraints.maxWidth);
        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Коллекция', style: GText.headline(constraints.maxWidth >= 768 ? 36 : 30)),
            const SizedBox(height: 20),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in _Tab.values) ...[
                    GNavPill(label: _tabLabels[t]!, active: _tab == t, onPressed: () => _select(t)),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        );

        final body = switch (_tab) {
          _Tab.tracks => _LikedTracks(searchController: _searchController),
          _Tab.playlists => const _Playlists(),
          _Tab.albums => const _Albums(),
          _Tab.artists => const _Artists(),
        };

        return Scrollbar(
          child: CustomScrollView(
            primary: true,
            slivers: [
              SliverToBoxAdapter(
                child: GPageFrame(
                  padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, 0),
                  child: header,
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  (constraints.maxWidth - GLayout.maxContentWidth).clamp(0, double.infinity) / 2 + padding.left,
                  0,
                  (constraints.maxWidth - GLayout.maxContentWidth).clamp(0, double.infinity) / 2 + padding.right,
                  48,
                ),
                sliver: body,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LikedTracks extends StatelessWidget {
  const _LikedTracks({required this.searchController});

  final TextEditingController searchController;

  Future<void> _download(List<SimpleTrackDto> tracks, DownloadMode mode) async {
    showAppSuccess('Скачивание ${tracks.length} ${plural(tracks.length, 'трека', 'треков', 'треков')} началось...');
    try {
      final paths = await downloadLikedTracksAction(tracks, toCache: mode == DownloadMode.cache);
      showAppSuccess(
        mode == DownloadMode.cache ? 'Любимые треки сохранены в кэш' : 'Сохранено файлов: ${paths.length}',
      );
    } on Object catch (e) {
      showAppError('Ошибка при скачивании: $e');
    }
  }

  Future<void> _deleteDownloaded(BuildContext context, List<SimpleTrackDto> tracks) async {
    final ok = await showGConfirm(
      context,
      title: 'Удалить всё?',
      message: 'Удалить все скачанные любимые треки из кэша приложения?',
      confirmLabel: 'Удалить',
      destructive: true,
    );
    if (!ok) return;
    try {
      final deleted = await deleteAllLikedTracksAction(tracks);
      if (deleted > 0) showAppSuccess('Удалено треков: $deleted');
    } on Object catch (e) {
      showAppError('Ошибка при удалении: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final tracks = likedTracksSignal();
        final loading = isLibraryLoadingSignal();
        final downloaded = downloadedTracksSignal();
        final busy = isDownloadingAllLikedTracksSignal();
        final query = librarySearchQuerySignal();
        final anyDownloaded = tracks.any((t) => downloaded.contains(t.id));
        final totalMs = tracks.fold<int>(0, (a, t) => a + t.durationMs);

        final toolbar = Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: GSearchField(
                  controller: searchController,
                  placeholder: 'Поиск в «Мне нравится»',
                  onChanged: setLibrarySearchQuery,
                ),
              ),
              GButton(
                label: 'Слушать',
                glyph: GGlyphKind.play,
                onPressed: tracks.isEmpty ? null : () => unawaited(PlaybackController.playLikedTrack(tracks.first.id)),
              ),
              GMenu(
                items: () => [
                  GMenuItem(
                    label: 'В кэш приложения',
                    icon: LucideIcons.hardDriveDownload,
                    onSelected: () => unawaited(_download(tracks, DownloadMode.cache)),
                  ),
                  GMenuItem(
                    label: 'В отдельные файлы',
                    icon: LucideIcons.fileMusic,
                    onSelected: () => unawaited(_download(tracks, DownloadMode.files)),
                  ),
                ],
                builder: (context, menu) => GCircleButton(
                  icon: LucideIcons.download,
                  tooltip: busy ? 'Скачивание…' : 'Скачать всё',
                  onPressed: tracks.isEmpty || busy ? null : () => menu.open(),
                ),
              ),
              if (anyDownloaded)
                GCircleButton(
                  icon: LucideIcons.trash2,
                  tooltip: 'Удалить всё из кэша',
                  onPressed: () => unawaited(_deleteDownloaded(context, tracks)),
                ),
              if (tracks.isNotEmpty)
                Text(
                  '${tracks.length} ${plural(tracks.length, 'трек', 'трека', 'треков')} · ${formatTotalDuration(totalMs)}',
                  style: GText.xs(color: GColors.mutedForeground),
                ),
            ],
          ),
        );

        if (tracks.isEmpty) {
          return SliverList.list(
            children: [
              toolbar,
              if (loading)
                const GLoader()
              else
                GEmptyState(
                  icon: LucideIcons.heart,
                  title: query.isEmpty ? 'Здесь будут ваши любимые треки' : 'Ничего не найдено',
                  message: query.isEmpty ? 'Нажмите на сердечко у трека, чтобы добавить его сюда.' : null,
                ),
            ],
          );
        }

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(child: toolbar),
            const SliverToBoxAdapter(child: TrackListHeader()),
            SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (context, i) {
                final t = tracks[i];
                return TrackRow(
                  key: ValueKey('liked_${t.id}'),
                  track: t,
                  onPlay: () => unawaited(PlaybackController.playLikedTrack(t.id)),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _Playlists extends StatelessWidget {
  const _Playlists();

  Future<void> _create(BuildContext context) async {
    final title = await showGPrompt(
      context,
      title: 'Новый плейлист',
      placeholder: 'Название',
      confirmLabel: 'Создать',
    );
    if (title == null) return;
    final ok = await createPlaylistAction(title, isPublic: false);
    ok ? showAppSuccess('Плейлист создан') : showAppError('Не удалось создать плейлист');
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final playlists = playlistsSignal();
        final liked = likedTracksSignal();
        return SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GButton(
                label: 'Новый плейлист',
                icon: LucideIcons.plus,
                variant: GButtonVariant.secondary,
                onPressed: () => unawaited(_create(context)),
              ),
              const SizedBox(height: 24),
              MediaGrid(
                children: [
                  MediaTile(
                    title: 'Мне нравится',
                    subtitle: liked.isEmpty ? 'Ваши лайки' : '${liked.length} ${plural(liked.length, 'трек', 'трека', 'треков')}',
                    cover: const LikedCover(),
                    onTap: () => navigateTo(AppSection.liked),
                  ),
                  for (final p in playlists.where((p) => p.kind != 3))
                    MediaTile(
                      title: p.title,
                      subtitle: [
                        '${p.trackCount} ${plural(p.trackCount, 'трек', 'трека', 'треков')}',
                        if (!p.isPublic) 'приватный',
                      ].join(' · '),
                      coverUrl: p.coverUrl,
                      icon: LucideIcons.listMusic,
                      onTap: () => navigateTo(AppSection.playlist, '${p.uid}:${p.kind}'),
                      menu: () => [
                        GMenuItem(
                          label: 'Слушать',
                          icon: LucideIcons.play,
                          onSelected: () => unawaited(PlaybackController.playPlaylist('${p.uid}', p.kind)),
                        ),
                        GMenuItem(
                          label: 'Открыть',
                          icon: LucideIcons.arrowUpRight,
                          onSelected: () => navigateTo(AppSection.playlist, '${p.uid}:${p.kind}'),
                        ),
                      ],
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

class _Albums extends StatelessWidget {
  const _Albums();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final albums = likedAlbumsSignal();
        if (albums.isEmpty) {
          return const SliverToBoxAdapter(
            child: GEmptyState(
              icon: LucideIcons.disc3,
              title: 'Нет альбомов',
              message: 'Добавляйте альбомы в коллекцию со страницы альбома.',
            ),
          );
        }
        return SliverToBoxAdapter(
          child: MediaGrid(
            children: [
              for (final a in albums)
                MediaTile(
                  title: a.title,
                  subtitle: [artistNames(a.artists), if (a.year != null) '${a.year}'].where((s) => s.isNotEmpty).join(' · '),
                  coverUrl: a.coverUrl,
                  icon: LucideIcons.disc3,
                  onTap: () => navigateTo(AppSection.album, a.id),
                  menu: () => [
                    GMenuItem(
                      label: 'Слушать',
                      icon: LucideIcons.play,
                      onSelected: () {
                        final id = int.tryParse(a.id);
                        if (id != null) unawaited(PlaybackController.playAlbum(id));
                      },
                    ),
                    GMenuItem(
                      label: 'Убрать из коллекции',
                      icon: LucideIcons.heartOff,
                      onSelected: () async {
                        if (await removeLikedAlbumAction(a.id)) unawaited(refreshLikedAlbums());
                      },
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

class _Artists extends StatelessWidget {
  const _Artists();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final artists = likedArtistsSignal();
        if (artists.isEmpty) {
          return const SliverToBoxAdapter(
            child: GEmptyState(
              icon: LucideIcons.user,
              title: 'Нет исполнителей',
              message: 'Отмечайте исполнителей сердечком на их странице.',
            ),
          );
        }
        return SliverToBoxAdapter(
          child: MediaGrid(
            minTileWidth: 130,
            maxColumns: 7,
            children: [
              for (final a in artists)
                MediaTile(
                  title: a.name,
                  subtitle: 'Исполнитель',
                  coverUrl: a.coverUrl,
                  circle: true,
                  icon: LucideIcons.user,
                  onTap: () => navigateTo(AppSection.artist, a.id),
                  menu: () => [
                    GMenuItem(
                      label: 'Моя волна по исполнителю',
                      icon: LucideIcons.radio,
                      onSelected: () => unawaited(PlaybackController.startArtistWave(a.id)),
                    ),
                    GMenuItem(
                      label: 'Убрать из любимых',
                      icon: LucideIcons.heartOff,
                      onSelected: () async {
                        if (await removeLikedArtistAction(a.id)) {
                          unawaited(refreshLikedArtists());
                          showAppSuccess('Исполнитель удален из любимых');
                        }
                      },
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
