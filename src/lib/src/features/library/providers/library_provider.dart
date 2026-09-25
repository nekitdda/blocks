import 'dart:async';

import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/auth/providers/auth_provider.dart';
import 'package:youmuz/src/features/core/services/rust_bridge.dart';
import 'package:youmuz/src/features/playback/providers/playback_provider.dart';
import 'package:youmuz/src/rust/api/content.dart';
import 'package:youmuz/src/rust/api/library.dart';
import 'package:youmuz/src/rust/api/models.dart';

final FlutterSignal<List<SimpleTrackDto>> likedTracksSignal =
    signal<List<SimpleTrackDto>>([]);
final FlutterSignal<List<SimplePlaylistDto>> playlistsSignal =
    signal<List<SimplePlaylistDto>>([]);
final FlutterSignal<List<SimpleAlbumDto>> likedAlbumsSignal =
    signal<List<SimpleAlbumDto>>([]);
final FlutterSignal<List<SimpleArtistDto>> likedArtistsSignal =
    signal<List<SimpleArtistDto>>([]);
final FlutterSignal<bool> isLibraryLoadingSignal = signal<bool>(false);
final FlutterSignal<String> librarySearchQuerySignal = signal<String>('');
final FlutterSignal<Set<String>> downloadedTracksSignal = signal<Set<String>>(
  {},
);
final FlutterSignal<Set<String>> downloadingTracksSignal = signal<Set<String>>(
  {},
);

StreamSubscription<List<SimpleTrackDto>>? _likedSub;
Timer? _librarySearchDebounce;

Future<void> initLibrary() async {
  // Load only playlists as they are lightweight and might be needed for navigation
  await refreshPlaylists();
  await refreshDownloadedTracks();
  // Liked tracks are loaded on demand when the library screen is opened
}

Timer? _downloadedRefreshDebounce;

/// Coalesce downloaded-track refreshes.
///
/// One refresh per finished download turned a batch of N tracks into N full
/// `getDownloadedTrackIds` fetches, each replacing the `Set` and therefore
/// invalidating `downloadedTracksSignal` in every visible track tile.
Future<void> refreshDownloadedTracks() {
  _downloadedRefreshDebounce?.cancel();
  final completer = Completer<void>();
  _downloadedRefreshDebounce = Timer(
    const Duration(milliseconds: 500),
    () async {
      final ids = await runRustFetch((ctx) => getDownloadedTrackIds(ctx: ctx));
      if (ids != null) {
        downloadedTracksSignal.value = ids.toSet();
      }
      if (!completer.isCompleted) completer.complete();
    },
  );
  return completer.future;
}

Future<void> refreshPlaylists() async {
  final playlists = await runRustFetch((ctx) => getPlaylists(ctx: ctx));
  if (playlists != null) {
    playlistsSignal.value = playlists;
  }
}

Future<void> refreshLikedAlbums() async {
  final albums = await runRustFetch((ctx) => getLikedAlbums(ctx: ctx));
  if (albums != null) {
    likedAlbumsSignal.value = albums;
  }
}

Future<void> refreshLikedArtists() async {
  final artists = await runRustFetch((ctx) => getLikedArtists(ctx: ctx));
  if (artists != null) {
    likedArtistsSignal.value = artists;
  }
}

Future<bool> addLikedAlbumAction(String albumId) async {
  final id = int.tryParse(albumId);
  if (id == null) return false;

  final success = await runRustAction(
    (ctx) => addLikedAlbum(ctx: ctx, albumId: id),
  );
  return success;
}

Future<bool> removeLikedAlbumAction(String albumId) async {
  final id = int.tryParse(albumId);
  if (id == null) return false;

  final success = await runRustAction(
    (ctx) => removeLikedAlbum(ctx: ctx, albumId: id),
  );
  return success;
}

Future<bool> addLikedArtistAction(String artistId) async {
  if (artistId.isEmpty) return false;

  final success = await runRustAction(
    (ctx) => addLikedArtist(ctx: ctx, artistId: artistId),
  );
  return success;
}

Future<bool> removeLikedArtistAction(String artistId) async {
  if (artistId.isEmpty) return false;

  final success = await runRustAction(
    (ctx) => removeLikedArtist(ctx: ctx, artistId: artistId),
  );
  return success;
}

Future<bool> addDislikedArtistAction(String artistId) async {
  if (artistId.isEmpty) return false;

  final success = await runRustAction(
    (ctx) => addDislikedArtist(ctx: ctx, artistId: artistId),
  );
  return success;
}

Future<bool> removeDislikedArtistAction(String artistId) async {
  if (artistId.isEmpty) return false;

  final success = await runRustAction(
    (ctx) => removeDislikedArtist(ctx: ctx, artistId: artistId),
  );
  return success;
}

Future<bool> addLikedPlaylistAction(String ownerUid, int kind) async {
  final uid = BigInt.tryParse(ownerUid);
  if (uid == null) return false;

  final success = await runRustAction(
    (ctx) => addLikedPlaylist(ctx: ctx, ownerUid: uid, kind: kind),
  );
  return success;
}

Future<bool> removeLikedPlaylistAction(String ownerUid, int kind) async {
  final uid = BigInt.tryParse(ownerUid);
  if (uid == null) return false;

  final success = await runRustAction(
    (ctx) => removeLikedPlaylist(ctx: ctx, ownerUid: uid, kind: kind),
  );
  return success;
}

Future<void> refreshLikedTracks({String? query, bool force = false}) async {
  if (!force &&
      query == null &&
      likedTracksSignal.value.isNotEmpty &&
      _likedSub != null) {
    return;
  }

  final ctx = appContextSignal.value;
  if (ctx == null) return;

  // Cancel previous subscription immediately
  final oldSub = _likedSub;
  _likedSub = null;
  unawaited(oldSub?.cancel());

  // Do not clear the list immediately to avoid flickering.
  // It will be cleared upon receiving the first chunk or reset signal.
  isLibraryLoadingSignal.value = true;

  // A monotonic counter, not the subscription identity. `listen()` runs
  // synchronously for an already-emitted stream, so during the first chunks
  // `sub` is still null and `sub != _likedSub` compared `null != null` — the
  // generation guard silently passed for every stale emission.
  final generation = ++_likedGeneration;
  var isFirstChunk = true;

  final sub = likedTracksStream(ctx: ctx, query: query).listen(
    (chunk) {
      if (generation != _likedGeneration) return;

      if (chunk.isEmpty) {
        if (isFirstChunk) {
          // Second empty chunk in a row or initial empty chunk when already
          // expecting first means the list is truly empty.
          likedTracksSignal.value = [];
        } else {
          // First empty chunk serves as a reset signal for a new data sequence:
          // the next non-empty chunk REPLACES the list.
          isFirstChunk = true;
        }
      } else if (isFirstChunk) {
        likedTracksSignal.value = chunk;
        isFirstChunk = false;
      } else {
        // Append, deduplicating against BOTH the current list and the chunk
        // itself. Only checking the signal let a chunk that repeats an id
        // append that id twice.
        final seen = likedTracksSignal.value.map((t) => t.id).toSet();
        final uniqueNewTracks = <SimpleTrackDto>[];
        for (final t in chunk) {
          if (seen.add(t.id)) uniqueNewTracks.add(t);
        }

        if (uniqueNewTracks.isNotEmpty) {
          likedTracksSignal.value = [
            ...likedTracksSignal.value,
            ...uniqueNewTracks,
          ];
        }
      }
    },
    onDone: () {
      if (generation != _likedGeneration) return;
      isLibraryLoadingSignal.value = false;
    },
    onError: (_) {
      if (generation != _likedGeneration) return;
      isLibraryLoadingSignal.value = false;
    },
  );
  _likedSub = sub;
}

int _likedGeneration = 0;

/// Apply a `LikedTracksChanged` event from the audio event stream.
///
/// This signal has two writers: the chunked stream above and this event. The
/// event carries the FULL unfiltered library, so writing it verbatim replaced
/// whatever search results the user was looking at.
void onLikedTracksChanged(List<SimpleTrackDto> tracks) {
  final query = librarySearchQuerySignal.value.trim().toLowerCase();
  if (query.isEmpty) {
    likedTracksSignal.value = tracks;
    return;
  }
  likedTracksSignal.value = tracks
      .where(
        (t) =>
            t.title.toLowerCase().contains(query) ||
            (t.album ?? '').toLowerCase().contains(query) ||
            t.artists.any((a) => a.name.toLowerCase().contains(query)),
      )
      .toList();
}

/// Reset every library signal. Called on logout so the previous account's data
/// does not survive into the next session.
void clearLibraryState() {
  _likedGeneration++;
  unawaited(_likedSub?.cancel());
  _likedSub = null;
  _librarySearchDebounce?.cancel();
  _downloadedRefreshDebounce?.cancel();
  likedTracksSignal.value = [];
  playlistsSignal.value = [];
  likedAlbumsSignal.value = [];
  likedArtistsSignal.value = [];
  downloadedTracksSignal.value = {};
  downloadingTracksSignal.value = {};
  librarySearchQuerySignal.value = '';
  isLibraryLoadingSignal.value = false;
}

void setLibrarySearchQuery(String query) {
  final trimmedQuery = query.trim();
  librarySearchQuerySignal.value = trimmedQuery;

  _librarySearchDebounce?.cancel();

  if (trimmedQuery.isEmpty) {
    // Immediately reset search and request the full list
    unawaited(refreshLikedTracks(force: true));
    return;
  }

  _librarySearchDebounce = Timer(const Duration(milliseconds: 300), () {
    // Check if the query changed while waiting
    if (librarySearchQuerySignal.value == trimmedQuery) {
      unawaited(refreshLikedTracks(query: trimmedQuery, force: true));
    }
  });
}

Future<void> playTrackById(String trackId) async {
  await PlaybackController.playTrack(trackId);
}

Future<void> playLikedTrackById(String trackId) async {
  await PlaybackController.playLikedTrack(trackId);
}

Future<bool> addTrackToPlaylistAction(
  int kind,
  String trackId,
  String? albumId,
) async {
  final success = await runRustAction(
    (ctx) => addTrackToPlaylist(
      ctx: ctx,
      kind: kind,
      trackId: trackId,
      albumId: albumId,
    ),
  );
  if (success) await refreshPlaylists();
  return success;
}

Future<bool> removeTrackFromPlaylistAction(
  int kind,
  String trackId,
  String? albumId,
) async {
  final success = await runRustAction(
    (ctx) => removeTrackFromPlaylist(
      ctx: ctx,
      kind: kind,
      trackId: trackId,
      albumId: albumId,
    ),
  );
  if (success) await refreshPlaylists();
  return success;
}

Future<bool> moveTrackInPlaylistAction(
  int kind,
  int fromIndex,
  int toIndex,
  String trackId,
  String? albumId,
) async {
  final success = await runRustAction(
    (ctx) => moveTrackInPlaylist(
      ctx: ctx,
      kind: kind,
      fromIndex: fromIndex,
      toIndex: toIndex,
      trackId: trackId,
      albumId: albumId ?? '',
    ),
  );
  if (success) await refreshPlaylists();
  return success;
}

Future<bool> createPlaylistAction(
  String title, {
  required bool isPublic,
}) async {
  final success = await runRustAction(
    (ctx) => createPlaylist(ctx: ctx, title: title, isPublic: isPublic),
  );
  if (success) await refreshPlaylists();
  return success;
}

Future<bool> deletePlaylistAction(int kind) async {
  final success = await runRustAction(
    (ctx) => deletePlaylist(ctx: ctx, kind: kind),
  );
  if (success) await refreshPlaylists();
  return success;
}

Future<bool> renamePlaylistAction(int kind, String newTitle) async {
  final success = await runRustAction(
    (ctx) => renamePlaylist(ctx: ctx, kind: kind, newTitle: newTitle),
  );
  if (success) await refreshPlaylists();
  return success;
}

Future<bool> setPlaylistVisibilityAction(
  int kind, {
  required bool isPublic,
}) async {
  final success = await runRustAction(
    (ctx) => setPlaylistVisibility(ctx: ctx, kind: kind, isPublic: isPublic),
  );
  if (success) await refreshPlaylists();
  return success;
}

Future<bool> uploadTrackAction(String filePath, {int? playlistKind}) async {
  final success = await runRustAction(
    (ctx) => uploadUserTrack(
      ctx: ctx,
      filePath: filePath,
      playlistKind: playlistKind,
    ),
  );
  return success;
}

final FlutterSignal<bool> isDownloadingAllLikedTracksSignal = signal(false);

Future<List<String>> downloadLikedTracksAction(
  List<SimpleTrackDto> tracks, {
  required bool toCache,
}) async {
  if (isDownloadingAllLikedTracksSignal.value) return const [];

  final ctx = appContextSignal.value;
  if (ctx == null) return const [];

  isDownloadingAllLikedTracksSignal.value = true;

  try {
    final trackIds = toCache
        ? tracks
              .where((t) => !downloadedTracksSignal.value.contains(t.id))
              .map((t) => t.id)
              .toList()
        : tracks.map((track) => track.id).toList();

    if (trackIds.isEmpty) return const [];

    final paths = await downloadTracks(
      ctx: ctx,
      trackIds: trackIds,
      toCache: toCache,
      collectionName: toCache ? null : 'Любимые треки',
    );
    if (toCache) unawaited(refreshDownloadedTracks());
    return paths;
  } finally {
    isDownloadingAllLikedTracksSignal.value = false;
  }
}

Future<List<String>> downloadCollectionToFilesAction(
  List<SimpleTrackDto> tracks, {
  required String collectionName,
}) async {
  final ctx = appContextSignal.value;
  if (ctx == null || tracks.isEmpty) return const [];

  return await downloadTracks(
    ctx: ctx,
    trackIds: tracks.map((track) => track.id).toList(),
    toCache: false,
    collectionName: collectionName,
  );
}

Future<int> deleteAllLikedTracksAction(List<SimpleTrackDto> tracks) async {
  final ctx = appContextSignal.value;
  if (ctx == null) return 0;

  var deleted = 0;
  for (final track in tracks) {
    final downloadedTracks = downloadedTracksSignal.value;
    if (downloadedTracks.contains(track.id)) {
      await deleteDownloadedTrack(ctx: ctx, trackId: track.id);
      unawaited(refreshDownloadedTracks());
      deleted++;
    }
  }

  return deleted;
}
