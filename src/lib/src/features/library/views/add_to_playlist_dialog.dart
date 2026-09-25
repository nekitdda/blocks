import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/core/providers/notification_provider.dart';
import 'package:youmuz/src/features/core/views/widgets/rust_cached_image.dart';
import 'package:youmuz/src/features/library/providers/library_provider.dart';
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/ui/ui.dart';

/// "трек" / "трека" / "треков" for [n].
String _tracksWord(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return 'трек';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'трека';
  return 'треков';
}

class AddToPlaylistDialog extends StatefulWidget {
  final SimpleTrackDto track;

  const AddToPlaylistDialog({required this.track, super.key});

  static Future<void> show(BuildContext context, SimpleTrackDto track) {
    return showGDialog<void>(
      context,
      builder: (context) => AddToPlaylistDialog(track: track),
    );
  }

  @override
  State<AddToPlaylistDialog> createState() => _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends State<AddToPlaylistDialog> {
  /// Playlist the track is being added to; blocks repeated taps meanwhile.
  int? _pendingKind;
  bool _creating = false;

  bool get _busy => _pendingKind != null || _creating;

  Future<void> _addTo(SimplePlaylistDto playlist) async {
    if (mounted) setState(() => _pendingKind = playlist.kind);
    final success = await addTrackToPlaylistAction(
      playlist.kind,
      widget.track.id,
      widget.track.albumId,
    );
    if (mounted) Navigator.of(context).pop();
    if (success) {
      showAppSuccess("Трек добавлен в '${playlist.title}'");
    } else {
      showAppError('Ошибка при добавлении трека');
    }
  }

  Future<void> _createAndAdd() async {
    final title = await showGPrompt(
      context,
      title: 'Новый плейлист',
      placeholder: 'Название',
      confirmLabel: 'Создать',
    );
    if (title == null || !mounted) return;

    setState(() => _creating = true);
    final before = {for (final p in playlistsSignal.value) p.kind};
    // Refreshes `playlistsSignal` before returning.
    final created = await createPlaylistAction(title, isPublic: false);
    final playlist = created ? _findCreated(before, title) : null;
    if (mounted) setState(() => _creating = false);

    if (!created) {
      showAppError('Ошибка при создании плейлиста');
      return;
    }
    if (playlist == null) {
      showAppError('Плейлист "$title" создан, но трек в него не добавлен');
      return;
    }
    await _addTo(playlist);
  }

  /// The playlist that appeared after creating [title]: a new kind, preferably
  /// with that title; the highest kind if several qualify.
  SimplePlaylistDto? _findCreated(Set<int> before, String title) {
    final fresh = playlistsSignal.value
        .where((p) => !before.contains(p.kind))
        .toList();
    final named = fresh.where((p) => p.title == title).toList();
    final pool = named.isNotEmpty ? named : fresh;
    if (pool.isEmpty) return null;
    return pool.reduce((a, b) => a.kind >= b.kind ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final artists = track.artists.map((a) => a.name).join(', ');

    return SignalBuilder(
      builder: (context) {
        final playlists = playlistsSignal.value;
        return GDialog(
          title: 'Добавить в плейлист',
          description: artists.isEmpty
              ? track.title
              : '${track.title} — $artists',
          content: playlists.isEmpty
              // Column keeps the centring empty state at its natural height.
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GEmptyState(
                      icon: LucideIcons.listMusic,
                      title: 'У вас пока нет плейлистов',
                      message: 'Создайте новый — трек сразу окажется в нём',
                      compact: true,
                    ),
                  ],
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return _PlaylistRow(
                      playlist: playlist,
                      pending: _pendingKind == playlist.kind,
                      onTap: _busy ? null : () => _addTo(playlist),
                    );
                  },
                ),
          actions: [
            GButton(
              label: 'Отмена',
              variant: GButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(),
            ),
            GButton(
              label: 'Новый плейлист',
              icon: LucideIcons.plus,
              variant: GButtonVariant.secondary,
              loading: _creating,
              onPressed: _busy ? null : _createAndAdd,
            ),
          ],
        );
      },
    );
  }
}

/// Playlist row (`rounded-xl p-2`, hover `bg-secondary`).
class _PlaylistRow extends StatelessWidget {
  final SimplePlaylistDto playlist;
  final bool pending;
  final VoidCallback? onTap;

  const _PlaylistRow({
    required this.playlist,
    required this.pending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final coverUrl = playlist.coverUrl == null
        ? null
        : resolveCoverUrl(playlist.coverUrl!, (40 * dpr).round());

    return GPressable(
      onTap: onTap,
      semanticLabel: playlist.title,
      builder: (context, s) => AnimatedContainer(
        duration: GDurations.fast,
        curve: GCurves.standard,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: s.hovered || pending
              ? GColors.secondary
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(GRadius.xl),
          border: Border.all(
            color: s.focused ? GColors.ring : const Color(0x00000000),
          ),
        ),
        child: Row(
          children: [
            GCover(
              url: coverUrl,
              size: 40,
              radius: GRadius.md,
              icon: LucideIcons.listMusic,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    style: GText.sm(weight: GText.medium),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${playlist.trackCount} ${_tracksWord(playlist.trackCount)}',
                    style: GText.xs(color: GColors.mutedForeground),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (pending)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: GColors.mutedForeground,
                ),
              )
            else
              AnimatedOpacity(
                duration: GDurations.fast,
                opacity: s.hovered || s.focused ? 1 : 0,
                child: const Icon(
                  LucideIcons.plus,
                  size: 16,
                  color: GColors.foreground,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
