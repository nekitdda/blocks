import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/features/auth/providers/auth_provider.dart';
import 'package:youmuz/src/features/core/providers/navigation_provider.dart';
import 'package:youmuz/src/features/core/providers/notification_provider.dart';
import 'package:youmuz/src/features/core/views/widgets/download_menu.dart';
import 'package:youmuz/src/features/core/views/widgets/lyrics_view.dart';
import 'package:youmuz/src/features/core/views/widgets/track_details_dialog.dart';
import 'package:youmuz/src/features/library/providers/library_provider.dart';
import 'package:youmuz/src/features/playback/providers/playback_provider.dart';
import 'package:youmuz/src/rust/api/content.dart' as rust;
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Title with its version, e.g. "Трек (Remix)".
String trackTitle(SimpleTrackDto t) =>
    (t.version == null || t.version!.trim().isEmpty) ? t.title : '${t.title} (${t.version})';

String artistNames(List<TrackArtistDto> artists) =>
    artists.map((a) => a.name).where((n) => n.isNotEmpty).join(', ');

/// `m:ss` / `h:mm:ss`.
String formatDuration(int ms) {
  final total = (ms / 1000).round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// "1 ч 12 мин" / "34 мин".
String formatTotalDuration(int ms) {
  final minutes = (ms / 60000).round();
  if (minutes >= 60) return '${minutes ~/ 60} ч ${minutes % 60} мин';
  return '$minutes мин';
}

/// Russian plural: plural(5, 'трек', 'трека', 'треков').
String plural(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

Future<void> downloadTrack(SimpleTrackDto track, DownloadMode mode) async {
  final ctx = appContextSignal.value;
  if (ctx == null) return;
  showAppSuccess(
    mode == DownloadMode.cache ? 'Скачивание в кэш началось...' : 'Скачивание в файл началось...',
  );
  downloadingTracksSignal.value = {...downloadingTracksSignal.value, track.id};
  try {
    final paths = await rust.downloadTracks(
      ctx: ctx,
      trackIds: [track.id],
      toCache: mode == DownloadMode.cache,
    );
    if (!identical(appContextSignal.value, ctx)) return;
    if (mode == DownloadMode.cache) {
      showAppSuccess('Трек скачан');
      unawaited(refreshDownloadedTracks());
    } else {
      showAppSuccess('Трек сохранен: ${paths.isEmpty ? '' : paths.first}');
    }
  } on Object catch (e) {
    if (identical(appContextSignal.value, ctx)) showAppError('Ошибка: $e');
  } finally {
    downloadingTracksSignal.value = {...downloadingTracksSignal.value}..remove(track.id);
  }
}

Future<void> _deleteDownloaded(SimpleTrackDto track) async {
  final ctx = appContextSignal.value;
  if (ctx == null) return;
  try {
    await rust.deleteDownloadedTrack(ctx: ctx, trackId: track.id);
    showAppSuccess('Трек удален из загрузок');
    unawaited(refreshDownloadedTracks());
  } on Object catch (e) {
    showAppError('Ошибка: $e');
  }
}

/// Downloads a whole album/playlist into the app cache or into files.
Future<void> downloadCollection(
  List<SimpleTrackDto> tracks,
  DownloadMode mode, {
  required String collectionName,
}) async {
  if (tracks.isEmpty) return;
  showAppSuccess(
    mode == DownloadMode.cache ? 'Скачивание в кэш началось...' : 'Скачивание в файлы началось...',
  );
  try {
    if (mode == DownloadMode.cache) {
      final ctx = appContextSignal.value;
      if (ctx == null) return;
      final ids = tracks
          .where((t) => !downloadedTracksSignal.value.contains(t.id))
          .map((t) => t.id)
          .toList();
      if (ids.isNotEmpty) {
        await rust.downloadTracks(ctx: ctx, trackIds: ids, toCache: true);
        unawaited(refreshDownloadedTracks());
      }
      showAppSuccess('Сохранено в кэш');
    } else {
      final paths = await downloadCollectionToFilesAction(tracks, collectionName: collectionName);
      showAppSuccess('Сохранено файлов: ${paths.length}');
    }
  } on Object catch (e) {
    showAppError('Ошибка при скачивании: $e');
  }
}

/// Menu entries for [downloadCollection].
List<GMenuItem> downloadCollectionItems(List<SimpleTrackDto> tracks, String collectionName) => [
  GMenuItem(
    label: 'В кэш приложения',
    icon: LucideIcons.hardDriveDownload,
    onSelected: () => unawaited(downloadCollection(tracks, DownloadMode.cache, collectionName: collectionName)),
  ),
  GMenuItem(
    label: 'В отдельные файлы',
    icon: LucideIcons.fileMusic,
    onSelected: () => unawaited(downloadCollection(tracks, DownloadMode.files, collectionName: collectionName)),
  ),
];

/// Context-menu entries shared by every track list and the player.
List<GMenuItem> trackMenuItems(
  BuildContext context,
  SimpleTrackDto track, {
  List<GMenuItem> leading = const [],
  List<GMenuItem> trailing = const [],
}) {
  final playlists = playlistsSignal.value;
  final downloaded = downloadedTracksSignal.value.contains(track.id);
  final albumId = track.albumId;
  final artists = track.artists.where((a) => a.id.isNotEmpty).toList();

  return [
    ...leading,
    GMenuItem(
      label: 'Добавить в плейлист',
      icon: LucideIcons.listPlus,
      children: [
        for (final p in playlists)
          GMenuItem(
            label: p.title,
            icon: LucideIcons.listMusic,
            onSelected: () async {
              final ok = await addTrackToPlaylistAction(p.kind, track.id, albumId);
              ok ? showAppSuccess('Добавлено в плейлист') : showAppError('Ошибка при добавлении');
            },
          ),
      ],
    ),
    GMenuItem(
      label: 'Моя волна по треку',
      icon: LucideIcons.radio,
      onSelected: () => unawaited(PlaybackController.startTrackWave(track.id, track.title)),
    ),
    const GMenuItem.divider(),
    if (albumId != null && albumId.isNotEmpty)
      GMenuItem(
        label: 'Перейти к альбому',
        icon: LucideIcons.disc3,
        onSelected: () => navigateTo(AppSection.album, albumId),
      ),
    if (artists.length == 1)
      GMenuItem(
        label: 'Перейти к исполнителю',
        icon: LucideIcons.user,
        onSelected: () => navigateTo(AppSection.artist, artists.first.id),
      )
    else if (artists.length > 1)
      GMenuItem(
        label: 'Исполнители',
        icon: LucideIcons.users,
        children: [
          for (final a in artists)
            GMenuItem(
              label: a.name,
              icon: LucideIcons.user,
              onSelected: () => navigateTo(AppSection.artist, a.id),
            ),
        ],
      ),
    GMenuItem(
      label: 'Открыть текст',
      icon: LucideIcons.micVocal,
      onSelected: () => LyricsReaderDialog.show(context, track.id, track.title),
    ),
    GMenuItem(
      label: 'О треке',
      icon: LucideIcons.info,
      onSelected: () => TrackDetailsDialog.show(context, track.id),
    ),
    GMenuItem(
      label: 'Скопировать ссылку',
      icon: LucideIcons.link,
      onSelected: () async {
        final link = albumId != null
            ? 'https://music.yandex.ru/album/$albumId/track/${track.id}'
            : 'https://music.yandex.ru/track/${track.id}';
        await Clipboard.setData(ClipboardData(text: link));
        showAppSuccess('Ссылка скопирована');
      },
    ),
    const GMenuItem.divider(),
    GMenuItem(
      label: 'Скачать',
      icon: LucideIcons.download,
      children: [
        GMenuItem(
          label: 'В кэш приложения',
          icon: LucideIcons.hardDriveDownload,
          onSelected: () => unawaited(downloadTrack(track, DownloadMode.cache)),
        ),
        GMenuItem(
          label: 'В отдельный файл',
          icon: LucideIcons.fileMusic,
          onSelected: () => unawaited(downloadTrack(track, DownloadMode.files)),
        ),
      ],
    ),
    if (downloaded)
      GMenuItem(
        label: 'Удалить из загрузок',
        icon: LucideIcons.trash2,
        onSelected: () => unawaited(_deleteDownloaded(track)),
      ),
    GMenuItem(
      label: track.isDisliked ? 'Снова рекомендовать' : 'Не рекомендовать',
      icon: LucideIcons.ban,
      onSelected: () => unawaited(PlaybackController.toggleDislike(trackId: track.id)),
    ),
    ...trailing,
  ];
}
