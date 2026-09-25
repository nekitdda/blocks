import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/core/providers/navigation_provider.dart';
import 'package:youmuz/src/features/core/views/widgets/track_actions.dart';
import 'package:youmuz/src/features/library/providers/library_provider.dart';
import 'package:youmuz/src/features/playback/providers/playback_provider.dart';
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/ui/ui.dart';

enum TrackLeading { cover, number }

/// Track list row (`rounded-xl px-2 py-2 gap-4`, hover and current row
/// `bg-secondary`): cover with play overlay / equalizer, title (amber when
/// current), artists, album column, like, duration and a context menu.
class TrackRow extends StatefulWidget {
  const TrackRow({
    required this.track,
    required this.onPlay,
    super.key,
    this.index,
    this.leading = TrackLeading.cover,
    this.showAlbum = true,
    this.menuLeading = const [],
    this.menuTrailing = const [],
  });

  final SimpleTrackDto track;

  /// Starts playback in the list's context (album, playlist, liked, ...).
  final VoidCallback onPlay;
  final int? index;
  final TrackLeading leading;
  final bool showAlbum;
  final List<GMenuItem> menuLeading;
  final List<GMenuItem> menuTrailing;

  @override
  State<TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<TrackRow> {
  bool _menuOpen = false;

  SimpleTrackDto get _t => widget.track;

  void _activate(bool isCurrent) {
    if (isCurrent) {
      unawaited(PlaybackController.togglePlay());
    } else {
      widget.onPlay();
    }
  }

  List<GMenuItem> _menu() => trackMenuItems(
    context,
    _t,
    leading: widget.menuLeading,
    trailing: widget.menuTrailing,
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= GLayout.wideBreakpoint;
    return GMenu(
      items: _menu,
      alignmentOffset: Offset.zero,
      onOpen: () => setState(() => _menuOpen = true),
      onClose: () {
        if (mounted) setState(() => _menuOpen = false);
      },
      builder: (context, menu) => SignalBuilder(builder: (context) {
        final isCurrent = currentTrackIdSignal() == _t.id;
        final isPlaying = isCurrent && isPlayingSignal();
        final liked = isCurrent ? isLikedSignal() : _t.isLiked;
        final downloading = downloadingTracksSignal().contains(_t.id);
        final downloaded = downloadedTracksSignal().contains(_t.id);

        return GPressable(
          onTap: () => _activate(isCurrent),
          onSecondaryTapUp: (d) => menu.open(position: d.localPosition),
          onLongPressStart: (d) => menu.open(position: d.localPosition),
          semanticLabel: '${isCurrent && isPlaying ? 'Пауза' : 'Играть'}: ${_t.title}',
          builder: (context, s) {
            final showControls = s.hovered || s.focused || _menuOpen;
            return AnimatedContainer(
              duration: GDurations.fast,
              curve: GCurves.standard,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: isCurrent || s.hovered || _menuOpen ? GColors.secondary : const Color(0x00000000),
                borderRadius: BorderRadius.circular(GRadius.xl),
                border: s.focused ? Border.all(color: GColors.ring) : null,
              ),
              child: Row(
                children: [
                  _Leading(
                    track: _t,
                    mode: widget.leading,
                    index: widget.index,
                    isCurrent: isCurrent,
                    isPlaying: isPlaying,
                    hovered: showControls,
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: _TitleBlock(track: _t, isCurrent: isCurrent)),
                  if (widget.showAlbum && wide && (_t.album?.isNotEmpty ?? false)) ...[
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 160,
                      child: _Link(
                        text: _t.album!,
                        style: GText.sm(color: GColors.mutedForeground),
                        onTap: _t.albumId == null ? null : () => navigateTo(AppSection.album, _t.albumId),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  if (downloading)
                    const Padding(
                      padding: EdgeInsets.all(6),
                      child: SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: GColors.mutedForeground),
                      ),
                    )
                  else if (downloaded)
                    const Padding(
                      padding: EdgeInsets.all(6),
                      child: Tooltip(
                        message: 'Скачан',
                        child: Icon(LucideIcons.hardDriveDownload, size: 14, color: GColors.mutedForeground),
                      ),
                    ),
                  AnimatedOpacity(
                    duration: GDurations.fast,
                    opacity: showControls || liked ? 1 : 0,
                    child: GIconButton(
                      glyph: GGlyphKind.heart,
                      padding: 6,
                      active: liked,
                      tooltip: liked ? 'Убрать из понравившихся' : 'Нравится',
                      onPressed: () => unawaited(PlaybackController.toggleLike(trackId: _t.id)),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      formatDuration(_t.durationMs),
                      textAlign: TextAlign.right,
                      style: GText.time(size: 12),
                    ),
                  ),
                  AnimatedOpacity(
                    duration: GDurations.fast,
                    opacity: showControls ? 1 : 0,
                    child: GIconButton(
                      icon: LucideIcons.ellipsis,
                      padding: 6,
                      tooltip: 'Ещё',
                      onPressed: () => menu.open(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      }),
    );
  }
}

class _Leading extends StatelessWidget {
  const _Leading({
    required this.track,
    required this.mode,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.hovered,
  });

  final SimpleTrackDto track;
  final TrackLeading mode;
  final int? index;
  final bool isCurrent;
  final bool isPlaying;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final Widget overlayIcon;
    if (isCurrent && isPlaying) {
      overlayIcon = hovered
          ? const GGlyph(GGlyphKind.pause, size: 16)
          : const GEqualizer(playing: true);
    } else {
      overlayIcon = const GGlyph(GGlyphKind.play, size: 16);
    }
    final showOverlay = hovered || isCurrent;

    if (mode == TrackLeading.number) {
      return SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: showOverlay
              ? overlayIcon
              : Text('${index ?? ''}', style: GText.time(size: 13)),
        ),
      );
    }
    return SizedBox.square(
      dimension: 44,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GCover(url: track.coverUrl, size: 44),
          AnimatedOpacity(
            duration: GDurations.fast,
            opacity: showOverlay ? 1 : 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: GColors.coverOverlay,
                borderRadius: BorderRadius.circular(GRadius.lg),
              ),
              child: Center(child: overlayIcon),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.track, required this.isCurrent});

  final SimpleTrackDto track;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final version = track.version?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            text: track.title,
            children: [
              if (version != null && version.isNotEmpty)
                TextSpan(
                  text: '  $version',
                  style: GText.sm(color: GColors.mutedForeground),
                ),
            ],
          ),
          style: GText.sm(
            weight: GText.medium,
            color: isCurrent ? GColors.brand : GColors.foreground,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        ArtistLinks(artists: track.artists),
      ],
    );
  }
}

/// Comma-separated artists, each opening the artist page.
class ArtistLinks extends StatelessWidget {
  const ArtistLinks({
    required this.artists,
    super.key,
    this.style,
  });

  final List<TrackArtistDto> artists;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? GText.xs(color: GColors.mutedForeground);
    if (artists.isEmpty) return Text('—', style: base);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < artists.length; i++) ...[
          Flexible(
            child: _Link(
              text: artists[i].name + (i < artists.length - 1 ? ',' : ''),
              style: base,
              onTap: artists[i].id.isEmpty ? null : () => navigateTo(AppSection.artist, artists[i].id),
            ),
          ),
          if (i < artists.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.text, required this.style, this.onTap});

  final String text;
  final TextStyle style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return GPressable(
      onTap: onTap,
      focusable: false,
      builder: (context, s) => Text(
        text,
        style: style.copyWith(
          color: s.hovered ? GColors.foreground : style.color,
          decoration: s.hovered ? TextDecoration.underline : null,
          decorationColor: GColors.foreground,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Column header above track lists ("Название ... Время").
class TrackListHeader extends StatelessWidget {
  const TrackListHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          Expanded(child: Text('Название', style: GText.xs(color: GColors.mutedForeground))),
          Text('Время', style: GText.xs(color: GColors.mutedForeground)),
          const SizedBox(width: 30),
        ],
      ),
    );
  }
}
