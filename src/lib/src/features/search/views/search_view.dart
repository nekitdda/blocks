import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/core/providers/navigation_provider.dart';
import 'package:youmuz/src/features/core/views/widgets/media_tile.dart';
import 'package:youmuz/src/features/core/views/widgets/track_actions.dart';
import 'package:youmuz/src/features/core/views/widgets/track_row.dart';
import 'package:youmuz/src/features/playback/providers/playback_provider.dart';
import 'package:youmuz/src/features/search/providers/search_provider.dart';
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Search results. On wide screens the query comes from the header field;
/// otherwise the page has its own field.
class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _controller = TextEditingController(text: searchQuerySignal.value);
  bool _allTracks = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final inlineField = width < GLayout.wideBreakpoint;
    return SignalBuilder(
      builder: (context) {
        final query = searchQuerySignal();
        final async = searchResultsSignal();
        final results = async.value;

        final children = <Widget>[
          Text('Поиск', style: GText.headline(width >= 768 ? 36 : 30)),
          const SizedBox(height: 20),
          if (inlineField) ...[
            GSearchField(
              controller: _controller,
              autofocus: query.isEmpty,
              height: 44,
              onChanged: setSearchQuery,
              onSubmitted: setSearchQuery,
            ),
            const SizedBox(height: 24),
          ],
        ];

        if (query.trim().isEmpty) {
          children.add(
            const GEmptyState(
              icon: LucideIcons.search,
              title: 'Что будем слушать?',
              message: 'Ищите треки, альбомы, исполнителей и плейлисты.',
            ),
          );
        } else if (async.isLoading && results == null) {
          children.add(const GLoader());
        } else if (async.hasError) {
          children.add(
            GEmptyState(
              icon: LucideIcons.circleAlert,
              title: 'Не удалось выполнить поиск',
              message: '${async.error}',
              action: GButton(
                label: 'Повторить',
                variant: GButtonVariant.secondary,
                onPressed: () => unawaited(searchResultsSignal.refresh()),
              ),
            ),
          );
        } else if (results == null || _isEmpty(results)) {
          children.add(
            GEmptyState(
              icon: LucideIcons.searchX,
              title: 'Ничего не найдено',
              message: 'По запросу «$query» ничего нет. Попробуйте иначе.',
            ),
          );
        } else {
          children.addAll(_results(results));
        }

        return GScrollPage(children: children);
      },
    );
  }

  bool _isEmpty(SearchResultsDto r) =>
      r.tracks.isEmpty && r.albums.isEmpty && r.artists.isEmpty && r.playlists.isEmpty;

  List<Widget> _results(SearchResultsDto r) {
    final tracks = _allTracks ? r.tracks : r.tracks.take(6).toList();
    return [
      if (r.tracks.isNotEmpty) ...[
        GSectionHeader(
          'Треки',
          bottom: 12,
          trailing: r.tracks.length > 6
              ? GTextAction(
                  label: _allTracks ? 'Свернуть' : 'Все ${r.tracks.length}',
                  onPressed: () => setState(() => _allTracks = !_allTracks),
                )
              : null,
        ),
        for (final t in tracks)
          TrackRow(
            key: ValueKey('search_${t.id}'),
            track: t,
            onPlay: () => unawaited(PlaybackController.playTrack(t.id)),
          ),
        const SizedBox(height: 40),
      ],
      if (r.artists.isNotEmpty) ...[
        const GSectionHeader('Исполнители'),
        MediaGrid(
          minTileWidth: 130,
          maxColumns: 7,
          children: [
            for (final a in r.artists.take(7))
              MediaTile(
                title: a.name,
                subtitle: 'Исполнитель',
                coverUrl: a.coverUrl,
                circle: true,
                icon: LucideIcons.user,
                onTap: () => navigateTo(AppSection.artist, a.id),
              ),
          ],
        ),
        const SizedBox(height: 40),
      ],
      if (r.albums.isNotEmpty) ...[
        const GSectionHeader('Альбомы'),
        MediaGrid(
          children: [
            for (final a in r.albums.take(12))
              MediaTile(
                title: a.title,
                subtitle: [artistNames(a.artists), if (a.year != null) '${a.year}'].where((s) => s.isNotEmpty).join(' · '),
                coverUrl: a.coverUrl,
                icon: LucideIcons.disc3,
                onTap: () => navigateTo(AppSection.album, a.id),
              ),
          ],
        ),
        const SizedBox(height: 40),
      ],
      if (r.playlists.isNotEmpty) ...[
        const GSectionHeader('Плейлисты'),
        MediaGrid(
          children: [
            for (final p in r.playlists.take(12))
              MediaTile(
                title: p.title,
                subtitle: '${p.trackCount} ${plural(p.trackCount, 'трек', 'трека', 'треков')}',
                coverUrl: p.coverUrl,
                icon: LucideIcons.listMusic,
                onTap: () => navigateTo(AppSection.playlist, '${p.uid}:${p.kind}'),
              ),
          ],
        ),
      ],
    ];
  }
}
