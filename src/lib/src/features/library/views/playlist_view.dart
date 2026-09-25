import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/auth/providers/auth_provider.dart';
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

/// Playlist page: cover, title, stats and actions next to the track list
/// (search, reorder, remove and upload for the account's own playlists).
class PlaylistView extends StatefulWidget {
  const PlaylistView({super.key, this.uid, this.kind});

  final String? uid;
  final String? kind;

  @override
  State<PlaylistView> createState() => _PlaylistViewState();
}

class _PlaylistViewState extends State<PlaylistView> {
  PlaylistDetailsDto? _playlist;
  List<SimpleTrackDto> _tracks = const [];
  bool _loading = true;
  String? _error;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  int _request = 0;

  int? get _uid => int.tryParse(widget.uid ?? '');
  int? get _kind => int.tryParse(widget.kind ?? '');

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uid;
    final kind = _kind;
    if (uid == null || kind == null) {
      setState(() {
        _loading = false;
        _error = 'Плейлист не выбран';
      });
      return;
    }
    final request = ++_request;
    setState(() => _loading = true);
    final query = _query;
    final result = await runRustFetch(
      (ctx) => rust.getPlaylistDetails(ctx: ctx, uid: uid, kind: kind, query: query.isEmpty ? null : query),
    );
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      if (result == null) {
        _error ??= _playlist == null ? 'Плейлист не найден' : null;
        return;
      }
      _error = null;
      if (query.isEmpty) _playlist = result;
      _playlist ??= result;
      _tracks = result.tracks;
    });
  }

  void _onSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _query = value.trim();
      unawaited(_load());
    });
  }

  bool get _owned => _playlist != null && _playlist!.uid == activeAccountUidSignal.value;

  Future<void> _upload() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['mp3', 'flac']);
    if (files.isEmpty || files.single.path == null) return;
    showAppSuccess('Загрузка трека началась...');
    final ok = await uploadTrackAction(files.single.path!, playlistKind: _playlist!.kind);
    if (ok) {
      showAppSuccess('Трек успешно загружен');
      unawaited(_load());
    } else {
      showAppError('Ошибка при загрузке трека');
    }
  }

  Future<void> _rename() async {
    final p = _playlist!;
    final title = await showGPrompt(context, title: 'Переименовать плейлист', initialValue: p.title);
    if (title == null || title == p.title) return;
    if (await renamePlaylistAction(p.kind, title)) {
      unawaited(_load());
    }
  }

  Future<void> _toggleVisibility() async {
    final p = _playlist!;
    if (await setPlaylistVisibilityAction(p.kind, isPublic: !p.isPublic)) {
      showAppSuccess(p.isPublic ? 'Плейлист стал приватным' : 'Плейлист стал публичным');
      unawaited(_load());
    }
  }

  Future<void> _delete() async {
    final p = _playlist!;
    final ok = await showGConfirm(
      context,
      title: 'Удалить плейлист?',
      message: '«${p.title}» будет удалён без возможности восстановления.',
      confirmLabel: 'Удалить',
      destructive: true,
    );
    if (!ok) return;
    if (await deletePlaylistAction(p.kind)) {
      showAppSuccess('Плейлист удалён');
      goBack();
    }
  }

  Future<void> _remove(SimpleTrackDto t) async {
    if (await removeTrackFromPlaylistAction(_playlist!.kind, t.id, t.albumId)) {
      showAppSuccess('Трек удалён из плейлиста');
      unawaited(_load());
    } else {
      showAppError('Не удалось удалить трек');
    }
  }

  Future<void> _move(int from, int to) async {
    if (to < 0 || to >= _tracks.length) return;
    final t = _tracks[from];
    setState(() {
      final list = [..._tracks];
      list.insert(to, list.removeAt(from));
      _tracks = list;
    });
    if (!await moveTrackInPlaylistAction(_playlist!.kind, from, to, t.id, t.albumId)) {
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _playlist;
    if (p == null) {
      if (_loading) return const GLoader();
      return GEmptyState(icon: LucideIcons.listMusic, title: _error ?? 'Плейлист не найден');
    }
    final totalMs = _tracks.fold<int>(0, (a, t) => a + t.durationMs);
    final owned = _owned;
    final searching = _query.isNotEmpty;

    return SignalBuilder(
      builder: (context) {
        final account = accountSignal();
        final owner = owned ? (account?.displayName ?? account?.login ?? 'Вы') : 'Другой пользователь';
        return CollectionPage(
          cover: (size) => GCover(url: p.coverUrl, size: size, radius: GRadius.x3l, icon: LucideIcons.listMusic),
          kindLabel: owned ? 'Мой плейлист' : 'Плейлист',
          title: p.title,
          stats: [
            ('Треков', '${p.trackCount}'),
            ('Длительность', formatTotalDuration(totalMs)),
            ('Автор', owner),
          ],
          primaryAction: ListenButton(
            onPressed: p.tracks.isEmpty ? null : () => unawaited(PlaybackController.playPlaylist('${p.uid}', p.kind)),
          ),
          actions: [
            GCircleButton(
              icon: LucideIcons.shuffle,
              size: 48,
              tooltip: 'Перемешать',
              active: isShuffledSignal(),
              onPressed: () => unawaited(PlaybackController.toggleShuffle()),
            ),
            if (owned)
              GCircleButton(
                icon: LucideIcons.pencil,
                size: 48,
                tooltip: 'Переименовать',
                onPressed: () => unawaited(_rename()),
              ),
            GCircleButton(
              icon: LucideIcons.share,
              size: 48,
              tooltip: 'Скопировать ссылку',
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: 'https://music.yandex.ru/users/${p.uid}/playlists/${p.kind}'),
                );
                showAppSuccess('Ссылка скопирована');
              },
            ),
            GMenu(
              items: () => [
                GMenuItem(
                  label: 'Скачать',
                  icon: LucideIcons.download,
                  children: downloadCollectionItems(_tracks, 'Плейлист - ${p.title}'),
                ),
                if (owned) ...[
                  GMenuItem(label: 'Загрузить трек', icon: LucideIcons.upload, onSelected: () => unawaited(_upload())),
                  GMenuItem(
                    label: p.isPublic ? 'Сделать приватным' : 'Сделать публичным',
                    icon: p.isPublic ? LucideIcons.lock : LucideIcons.globe,
                    onSelected: () => unawaited(_toggleVisibility()),
                  ),
                  const GMenuItem.divider(),
                  GMenuItem(
                    label: 'Удалить плейлист',
                    icon: LucideIcons.trash2,
                    destructive: true,
                    onSelected: () => unawaited(_delete()),
                  ),
                ],
              ],
              builder: (context, menu) => GCircleButton(
                icon: LucideIcons.ellipsis,
                size: 48,
                tooltip: 'Ещё',
                onPressed: () => menu.open(),
              ),
            ),
          ],
          footer: p.isPublic ? 'Публичный плейлист' : 'Приватный плейлист',
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                child: GSearchField(
                  controller: _searchController,
                  placeholder: 'Поиск в плейлисте',
                  onChanged: _onSearch,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: TrackListHeader()),
            if (_tracks.isEmpty)
              SliverToBoxAdapter(
                child: _loading
                    ? const GLoader()
                    : GEmptyState(
                        icon: LucideIcons.listMusic,
                        title: searching ? 'Ничего не найдено' : 'В плейлисте пока нет треков',
                        compact: true,
                      ),
              )
            else
              SliverList.builder(
                itemCount: _tracks.length,
                itemBuilder: (context, i) {
                  final t = _tracks[i];
                  return TrackRow(
                    key: ValueKey('pl_${t.id}_$i'),
                    track: t,
                    onPlay: () => unawaited(PlaybackController.playPlaylistTrack('${p.uid}', p.kind, t.id)),
                    menuTrailing: owned
                        ? [
                            const GMenuItem.divider(),
                            if (!searching && i > 0)
                              GMenuItem(
                                label: 'Переместить выше',
                                icon: LucideIcons.arrowUp,
                                onSelected: () => unawaited(_move(i, i - 1)),
                              ),
                            if (!searching && i < _tracks.length - 1)
                              GMenuItem(
                                label: 'Переместить ниже',
                                icon: LucideIcons.arrowDown,
                                onSelected: () => unawaited(_move(i, i + 1)),
                              ),
                            GMenuItem(
                              label: 'Удалить из плейлиста',
                              icon: LucideIcons.trash2,
                              destructive: true,
                              onSelected: () => unawaited(_remove(t)),
                            ),
                          ]
                        : const [],
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
