import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/core/providers/navigation_provider.dart';
import 'package:youmuz/src/features/core/providers/notification_provider.dart';
import 'package:youmuz/src/features/core/services/rust_bridge.dart';
import 'package:youmuz/src/features/core/views/widgets/collection_page.dart';
import 'package:youmuz/src/features/core/views/widgets/track_actions.dart';
import 'package:youmuz/src/features/core/views/widgets/track_row.dart';
import 'package:youmuz/src/features/library/providers/library_provider.dart';
import 'package:youmuz/src/features/playback/providers/playback_provider.dart';
import 'package:youmuz/src/rust/api/content.dart' as rust;
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/ui/ui.dart';

class AlbumView extends StatefulWidget {
  const AlbumView({super.key, this.albumId});

  final String? albumId;

  @override
  State<AlbumView> createState() => _AlbumViewState();
}

class _AlbumViewState extends State<AlbumView> {
  AlbumDetailsDto? _album;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    if (likedAlbumsSignal.value.isEmpty) unawaited(refreshLikedAlbums());
  }

  Future<void> _load() async {
    final id = int.tryParse(widget.albumId ?? '');
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    final album = await runRustFetch((ctx) => rust.getAlbumDetails(ctx: ctx, albumId: id));
    if (!mounted) return;
    setState(() {
      _album = album;
      _loading = false;
    });
  }

  Future<void> _toggleLike(bool liked) async {
    final a = _album!;
    final ok = liked ? await removeLikedAlbumAction(a.id) : await addLikedAlbumAction(a.id);
    if (ok) {
      showAppSuccess(liked ? 'Альбом удалён из коллекции' : 'Альбом добавлен в коллекцию');
      unawaited(refreshLikedAlbums());
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _album;
    if (a == null) {
      if (_loading) return const GLoader();
      return GEmptyState(
        icon: LucideIcons.disc3,
        title: widget.albumId == null ? 'Альбом не выбран' : 'Альбом не найден',
      );
    }
    final albumId = int.tryParse(a.id);
    final totalMs = a.tracks.fold<int>(0, (sum, t) => sum + t.durationMs);
    return SignalBuilder(
      builder: (context) {
        final liked = likedAlbumsSignal().any((x) => x.id == a.id);
        return CollectionPage(
          cover: (size) => GCover(url: a.coverUrl, size: size, radius: GRadius.x3l, icon: LucideIcons.disc3),
          kindLabel: a.year != null ? 'Альбом · ${a.year}' : 'Альбом',
          title: a.title,
          description: ArtistLinks(artists: a.artists, style: GText.sm(color: GColors.mutedForeground)),
          stats: [
            ('Треков', '${a.tracks.length}'),
            ('Длительность', formatTotalDuration(totalMs)),
            ('Год', a.year?.toString() ?? '—'),
          ],
          primaryAction: ListenButton(
            onPressed: albumId == null || a.tracks.isEmpty ? null : () => unawaited(PlaybackController.playAlbum(albumId)),
          ),
          actions: [
            GCircleButton(
              glyph: GGlyphKind.heart,
              size: 48,
              active: liked,
              tooltip: liked ? 'Убрать из коллекции' : 'Добавить в коллекцию',
              onPressed: () => unawaited(_toggleLike(liked)),
            ),
            GCircleButton(
              icon: LucideIcons.share,
              size: 48,
              tooltip: 'Скопировать ссылку',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: 'https://music.yandex.ru/album/${a.id}'));
                showAppSuccess('Ссылка скопирована');
              },
            ),
            GMenu(
              items: () => [
                GMenuItem(
                  label: 'Скачать',
                  icon: LucideIcons.download,
                  children: downloadCollectionItems(a.tracks, 'Альбом - ${a.title}'),
                ),
                for (final artist in a.artists.where((x) => x.id.isNotEmpty))
                  GMenuItem(
                    label: artist.name,
                    icon: LucideIcons.user,
                    onSelected: () => navigateTo(AppSection.artist, artist.id),
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
            const SliverToBoxAdapter(child: TrackListHeader()),
            SliverList.builder(
              itemCount: a.tracks.length,
              itemBuilder: (context, i) {
                final t = a.tracks[i];
                return TrackRow(
                  key: ValueKey('album_${t.id}'),
                  track: t,
                  index: i + 1,
                  leading: TrackLeading.number,
                  showAlbum: false,
                  onPlay: () {
                    if (albumId != null) unawaited(PlaybackController.playAlbumTrack(albumId, t.id));
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }
}
