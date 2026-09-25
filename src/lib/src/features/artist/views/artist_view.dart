import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/core/providers/navigation_provider.dart';
import 'package:youmuz/src/features/core/providers/notification_provider.dart';
import 'package:youmuz/src/features/core/services/rust_bridge.dart';
import 'package:youmuz/src/features/core/views/widgets/collection_page.dart';
import 'package:youmuz/src/features/core/views/widgets/media_tile.dart';
import 'package:youmuz/src/features/core/views/widgets/track_actions.dart';
import 'package:youmuz/src/features/core/views/widgets/track_row.dart';
import 'package:youmuz/src/features/library/providers/library_provider.dart';
import 'package:youmuz/src/features/playback/providers/playback_provider.dart';
import 'package:youmuz/src/rust/api/content.dart' as rust;
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Artist page: popular tracks (paged while scrolling) and albums.
class ArtistView extends StatefulWidget {
  const ArtistView({super.key, this.artistId});

  final String? artistId;

  @override
  State<ArtistView> createState() => _ArtistViewState();
}

class _ArtistViewState extends State<ArtistView> {
  static const _pageSize = 30;

  final _scroll = ScrollController();
  ArtistDetailsDto? _artist;
  List<SimpleTrackDto> _tracks = const [];
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_load());
    if (likedArtistsSignal.value.isEmpty) unawaited(refreshLikedArtists());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final a = _artist;
    if (a == null || _loadingMore || _tracks.length >= a.totalTracks) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 500) {
      unawaited(_loadMore());
    }
  }

  Future<void> _load() async {
    final id = widget.artistId;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    final details = await runRustFetch(
      (ctx) => rust.getArtistDetails(ctx: ctx, artistId: id, page: 0, pageSize: _pageSize),
    );
    if (!mounted) return;
    setState(() {
      _artist = details;
      _tracks = details?.tracks ?? const [];
      _page = 0;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    final id = widget.artistId;
    if (id == null) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    final details = await runRustFetch(
      (ctx) => rust.getArtistDetails(ctx: ctx, artistId: id, page: next, pageSize: _pageSize),
    );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (details == null || details.tracks.isEmpty) return;
      final seen = _tracks.map((t) => t.id).toSet();
      _tracks = [..._tracks, ...details.tracks.where((t) => seen.add(t.id))];
      _page = next;
    });
  }

  Future<void> _toggleLike(bool liked) async {
    final a = _artist!;
    final ok = liked ? await removeLikedArtistAction(a.id) : await addLikedArtistAction(a.id);
    if (ok) {
      showAppSuccess(liked ? 'Исполнитель удалён из любимых' : 'Исполнитель добавлен в любимые');
      unawaited(refreshLikedArtists());
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _artist;
    if (a == null) {
      if (_loading) return const GLoader();
      return GEmptyState(
        icon: LucideIcons.user,
        title: widget.artistId == null ? 'Артист не выбран' : 'Артист не найден',
      );
    }
    return SignalBuilder(
      builder: (context) {
        final liked = likedArtistsSignal().any((x) => x.id == a.id);
        return CollectionPage(
          scrollController: _scroll,
          cover: (size) => GCover(url: a.coverUrl, size: size, circle: true, icon: LucideIcons.user),
          kindLabel: 'Исполнитель',
          title: a.name,
          stats: [
            ('Треков', '${a.totalTracks}'),
            ('Альбомов', '${a.albums.length}'),
            ('В коллекции', liked ? 'Да' : 'Нет'),
          ],
          primaryAction: ListenButton(
            label: 'Моя волна',
            onPressed: () => unawaited(PlaybackController.startArtistWave(a.id)),
          ),
          actions: [
            GCircleButton(
              glyph: GGlyphKind.heart,
              size: 48,
              active: liked,
              tooltip: liked ? 'Убрать из любимых' : 'Добавить в любимые',
              onPressed: () => unawaited(_toggleLike(liked)),
            ),
            GMenu(
              items: () => [
                GMenuItem(
                  label: 'Скачать популярные',
                  icon: LucideIcons.download,
                  children: downloadCollectionItems(_tracks, 'Исполнитель - ${a.name}'),
                ),
                GMenuItem(
                  label: 'Не рекомендовать исполнителя',
                  icon: LucideIcons.ban,
                  onSelected: () async {
                    if (await addDislikedArtistAction(a.id)) showAppSuccess('Исполнитель не будет рекомендоваться');
                  },
                ),
              ],
              builder: (context, menu) => GCircleButton(
                icon: LucideIcons.ellipsis,
                size: 48,
                tooltip: 'Ещё',
                onPressed: () => menu.open(),
              ),
            ),
          ],
          slivers: [
            const SliverToBoxAdapter(child: GSectionHeader('Популярные треки', bottom: 12)),
            SliverList.builder(
              itemCount: _tracks.length,
              itemBuilder: (context, i) {
                final t = _tracks[i];
                return TrackRow(
                  key: ValueKey('artist_${t.id}'),
                  track: t,
                  onPlay: () => unawaited(PlaybackController.playTrack(t.id)),
                );
              },
            ),
            if (_loadingMore) const SliverToBoxAdapter(child: GLoader(padding: 16)),
            if (a.albums.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(8, 40, 8, 0),
                  child: GSectionHeader('Альбомы'),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: SliverToBoxAdapter(
                  child: MediaGrid(
                    maxColumns: 5,
                    children: [
                      for (final album in a.albums)
                        MediaTile(
                          title: album.title,
                          subtitle: album.year?.toString(),
                          coverUrl: album.coverUrl,
                          icon: LucideIcons.disc3,
                          onTap: () => navigateTo(AppSection.album, album.id),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
