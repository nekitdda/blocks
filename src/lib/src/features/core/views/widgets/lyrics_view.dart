import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/playback/providers/lyrics_provider.dart';
import 'package:youmuz/src/features/playback/providers/playback_provider.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Shared timing for the active-line transition. Colour, opacity *and* the
/// scroll that brings the line to its anchor all run on this, so nothing
/// arrives out of step with the rest.
const Duration _lyricTransitionDuration = Duration(milliseconds: 500);
const Curve _lyricTransitionCurve = Curves.easeOutCubic;

/// Karaoke word highlighting has to keep up with the singing, so it gets its
/// own short duration rather than [_lyricTransitionDuration].
const Duration _karaokeWordDuration = Duration(milliseconds: 150);

/// Where the active line settles, as a fraction of the viewport height.
const double _activeLineAnchor = 0.38;

/// Hovered (seekable) inactive line: `mutedForeground` lerped 55% towards
/// `foreground`.
const Color _lyricHoverColor = Color(0xFFC0BEB8);

/// Opacity once the last line is over and a long outro remains
/// ([hideLyricsOverlaySignal]). The lyrics sit on an opaque panel, so they
/// recede rather than vanish and stay tappable for seeking back.
const double _finishedOpacity = 0.35;

/// First index in [lines] whose time is past [currentMs], or `lines.length`
/// if none. `lines` is time-sorted, so this binary-searches instead of
/// scanning — called on every progress tick (~8/sec while playing).
int _upperBoundByTime(List<LyricItem> lines, int currentMs) {
  var lo = 0;
  var hi = lines.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].time.inMilliseconds > currentMs) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  return lo;
}

/// Every line shares one size and weight, so activating a line only changes
/// its colour and never reflows the column mid-scroll.
TextStyle _lyricTextStyle(double size, Color color) => GText.style(
  size,
  lineHeight: size * 1.22,
  weight: GText.semibold,
  color: color,
  tight: true,
);

/// Opacity of a line [offset] rows away from the active one (negative: already
/// sung). Upcoming lines stay readable and fade with distance; sung ones recede.
double _lineOpacity(int offset) {
  if (offset == 0) return 1;
  if (offset < 0) return 0.45;
  return (1.05 - offset * 0.15).clamp(0.4, 0.9);
}

/// Keeps a [GLoader]/[GEmptyState], which centre in all the space they get,
/// at its natural height inside a dialog.
Widget _dialogFit(Widget child) =>
    Column(mainAxisSize: MainAxisSize.min, children: [child]);

class LyricsWidget extends StatefulWidget {
  final String trackId;
  final bool visible;
  const LyricsWidget({required this.trackId, required this.visible, super.key});
  @override
  State<LyricsWidget> createState() => _LyricsWidgetState();
}

class _LyricsWidgetState extends State<LyricsWidget> {
  final ScrollController _scrollController = ScrollController();
  final FlutterSignal<int> _activeIndexSignal = signal<int>(-1);
  final FlutterSignal<String> _trackIdSignal = signal<String>('');
  final FlutterSignal<bool> _visibleSignal = signal<bool>(false);

  bool _initialScrollDone = false;

  /// One key per row of [_keyedLines], used to find the active row's layout.
  List<GlobalKey> _rowKeys = const [];
  List<LyricItem>? _keyedLines;

  EffectCleanup? _loadingTrackingCleanup;
  EffectCleanup? _progressSubscriptionCleanup;

  @override
  void initState() {
    super.initState();
    _initialScrollDone = !widget.visible;
    _trackIdSignal.value = widget.trackId;
    _visibleSignal.value = widget.visible;

    _progressSubscriptionCleanup = _setupProgressSubscription();
    _loadingTrackingCleanup = _setupLoadingTracking();
  }

  EffectCleanup _setupLoadingTracking() {
    return effect(() {
      if (!_visibleSignal.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) lyricsSuppressDimSignal.value = false;
        });
        return;
      }

      final lyricsState = lyricsSignal(_trackIdSignal.value).value;
      final isLoading = lyricsState.isLoading;
      final isEmpty = lyricsState.value?.items.isEmpty ?? false;
      final suppressDim = isLoading || isEmpty;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) lyricsSuppressDimSignal.value = suppressDim;
      });
    });
  }

  EffectCleanup _setupProgressSubscription() {
    return effect(() {
      if (!_visibleSignal.value) return;

      final trackId = _trackIdSignal.value;
      final lyricsState = lyricsSignal(trackId).value;
      if (!lyricsState.hasValue) return;

      final lines = lyricsState.value!.items;
      if (lines.isEmpty) return;

      final progress = trackProgressSignal.value;
      final currentMs = progress.positionMs.toInt();
      final durationMs = progress.durationMs.toInt();

      // Lines are time-sorted, so a binary search for the first line past
      // `currentMs` is enough — this runs on every progress tick (~8/sec).
      var activeIndex = _upperBoundByTime(lines, currentMs) - 1;

      if (activeIndex == -2) {
        activeIndex = lines.length - 1;
      } else if (activeIndex < 0) {
        activeIndex = 0;
      }

      // Read untracked: reading `.value` here subscribes this effect to
      // `_activeIndexSignal`, and the write below then re-queues the effect on
      // every progress tick. It converges (the equality check short-circuits
      // the second run) but doubles the work of the hottest effect in the app
      // and sits one change away from `throwCycleDetected()`.
      if (untracked(() => _activeIndexSignal.value) != activeIndex) {
        _activeIndexSignal.value = activeIndex;
      }

      if (activeIndex == lines.length - 1) {
        final lastLine = lines.last;
        if (lastLine is LyricLine) {
          final lastLineEndMs =
              lastLine.time.inMilliseconds + lastLine.duration.inMilliseconds;
          if (currentMs > lastLineEndMs + 1000) {
            final remainingMs = durationMs - currentMs;
            if (remainingMs > 5000) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !hideLyricsOverlaySignal.value) {
                  hideLyricsOverlaySignal.value = true;
                }
              });
            }
          }
        }
      }
    });
  }

  @override
  void didUpdateWidget(LyricsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trackId != oldWidget.trackId) {
      _initialScrollDone = !widget.visible;
      _activeIndexSignal.value = -1;
      hideLyricsOverlaySignal.value = false;

      _trackIdSignal.value = widget.trackId;
      _visibleSignal.value = widget.visible;
    } else if (widget.visible != oldWidget.visible) {
      _visibleSignal.value = widget.visible;
      if (widget.visible) {
        _initialScrollDone = false;
      }
    }
  }

  @override
  void dispose() {
    _progressSubscriptionCleanup?.call();
    _loadingTrackingCleanup?.call();
    _scrollController.dispose();
    super.dispose();
  }

  List<GlobalKey> _keysFor(List<LyricItem> lines) {
    if (!identical(lines, _keyedLines)) {
      _keyedLines = lines;
      _rowKeys = List.generate(lines.length, (_) => GlobalKey());
    }
    return _rowKeys;
  }

  /// Brings row [index] to [_activeLineAnchor]. Rows wrap to any height, so
  /// the offset comes from the row's own layout; asking only this viewport
  /// (not `Scrollable.ensureVisible`) keeps enclosing scroll views still.
  void _scrollToIndex(int index) {
    if (!mounted || !_scrollController.hasClients) return;
    if (index < 0 || index >= _rowKeys.length) return;
    final row = _rowKeys[index].currentContext?.findRenderObject();
    if (row == null || !row.attached) return;
    final viewport = RenderAbstractViewport.maybeOf(row);
    if (viewport == null) return;

    final position = _scrollController.position;
    final target = viewport
        .getOffsetToReveal(row, _activeLineAnchor)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);

    if (!_initialScrollDone) {
      _initialScrollDone = true;
      _scrollController.jumpTo(target);
    } else if ((position.pixels - target).abs() > 0.5) {
      // Same timing as the rows themselves, and an ease-*out* curve on
      // purpose: lines can follow each other faster than the animation
      // lasts, and a new `animateTo` restarts from zero velocity — with an
      // ease-in the scroll would visibly stall at every such hand-off.
      _scrollController.animateTo(
        target,
        duration: _lyricTransitionDuration,
        curve: _lyricTransitionCurve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();

    return SignalBuilder(
      builder: (context) {
        final lyricsAsync = lyricsSignal(widget.trackId).value;
        final hideOverlay = hideLyricsOverlaySignal.value;

        return AnimatedOpacity(
          duration: _lyricTransitionDuration,
          curve: _lyricTransitionCurve,
          opacity: hideOverlay ? _finishedOpacity : 1.0,
          child: lyricsAsync.map(
            data: (result) => result.items.isEmpty
                ? const GEmptyState(
                    icon: LucideIcons.micVocal,
                    title: 'Текст отсутствует',
                    message: 'Для этого трека текст не найден',
                  )
                : _buildLyrics(result),
            loading: () => const GLoader(),
            error: (Object e, _) => GEmptyState(
              icon: LucideIcons.circleAlert,
              title: 'Не удалось загрузить текст',
              message: e.toString(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLyrics(LyricsResult result) {
    final lines = result.items;
    final keys = _keysFor(lines);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewportHeight = constraints.maxHeight;
              final fontSize = constraints.maxWidth < 560 ? 24.0 : 30.0;

              return SignalBuilder(
                builder: (context) {
                  final activeIndex = _activeIndexSignal.value;

                  if (activeIndex != -1) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _scrollToIndex(activeIndex);
                    });
                  }

                  // Only a short fade at the very edges, so lines leaving the
                  // viewport are not cut off hard.
                  return ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00000000),
                        Color(0xFF000000),
                        Color(0xFF000000),
                        Color(0x00000000),
                      ],
                      stops: [0.0, 0.06, 0.94, 1.0],
                    ).createShader(rect),
                    blendMode: BlendMode.dstIn,
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.only(
                          top: viewportHeight * _activeLineAnchor,
                          bottom: viewportHeight * (1 - _activeLineAnchor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < lines.length; i++)
                              _LyricRow(
                                key: keys[i],
                                item: lines[i],
                                isActive: i == activeIndex,
                                offset: i - activeIndex,
                                fontSize: fontSize,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (result.providerName.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Источник: ${result.providerName}',
              style: GText.xs(color: GColors.mutedForeground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

/// One synced line: tap seeks to its start.
class _LyricRow extends StatefulWidget {
  final LyricItem item;
  final bool isActive;

  /// Rows from the active one; negative for lines already sung.
  final int offset;
  final double fontSize;

  const _LyricRow({
    required this.item,
    required this.isActive,
    required this.offset,
    required this.fontSize,
    super.key,
  });

  @override
  State<_LyricRow> createState() => _LyricRowState();
}

// Hover is tracked here rather than through `GPressable`: that one only
// reports hover while focusable, and a tab stop per lyric line would bury
// the rest of the page.
class _LyricRowState extends State<_LyricRow> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isActive = widget.isActive;
    final fontSize = widget.fontSize;
    if (item is LyricTimer) {
      return _LyricTimerWidget(
        item: item,
        isActive: isActive,
        height: fontSize * 1.6,
      );
    }

    final line = item as LyricLine;
    final hovered = _hovered && !isActive;
    final color = isActive
        ? GColors.foreground
        : (hovered ? _lyricHoverColor : GColors.mutedForeground);
    final style = _lyricTextStyle(fontSize, color);
    // Hover reacts at the UI pace; the line hand-off stays on the slower
    // shared timing.
    final duration = hovered ? GDurations.fast : _lyricTransitionDuration;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(PlaybackController.seekTo(line.time)),
          child: Semantics(
            button: true,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: fontSize * 0.27),
              child: AnimatedOpacity(
                duration: duration,
                curve: _lyricTransitionCurve,
                opacity: hovered ? 1.0 : _lineOpacity(widget.offset),
                // Word-synced lines use the karaoke layout whether or not
                // they are active, so activating a line changes colour only.
                child: (line.words?.isNotEmpty ?? false)
                    ? _KaraokeLineText(
                        line: line,
                        isActive: isActive,
                        style: style,
                      )
                    : AnimatedDefaultTextStyle(
                        duration: duration,
                        curve: _lyricTransitionCurve,
                        style: style,
                        child: Text(line.text),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders a lyric line word-by-word, highlighting each word as playback
/// position passes its start/end timing (karaoke-style), for providers that
/// supply word-synced timing (currently BetterLyrics).
///
/// Inactive lines are laid out exactly the same way — they just render every
/// word in the row colour, and let the row's own opacity do the dimming.
class _KaraokeLineText extends StatelessWidget {
  final LyricLine line;
  final bool isActive;
  final TextStyle style;

  const _KaraokeLineText({
    required this.line,
    required this.isActive,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    // Only the active line follows playback position. Subscribing every
    // visible row to `trackProgressSignal` would rebuild the whole viewport
    // eight times a second for highlighting that isn't even shown.
    if (!isActive) {
      return _KaraokeLine(
        words: line.words!,
        currentMs: 0,
        lineActive: false,
        style: style,
      );
    }

    return SignalBuilder(
      builder: (context) => _KaraokeLine(
        words: line.words!,
        currentMs: trackProgressSignal.value.positionMs.toInt(),
        lineActive: true,
        style: style,
      ),
    );
  }
}

/// How far singing has progressed through a line's words, expressed as the
/// count of fully-sung words plus the index of the word being sung right
/// now (or -1). Two different [currentMs] values can map to the same
/// signature — e.g. between two consecutive words, or during the silence
/// before the first one — which [_KaraokeLine] uses to skip rebuilding the
/// word row on progress ticks that don't actually change anything visible.
({int sungCount, int singingIndex}) _karaokeSignature(
  List<LyricWord> words,
  int currentMs,
) {
  var sungCount = 0;
  var singingIndex = -1;
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    if (currentMs >= word.end.inMilliseconds) {
      sungCount++;
    } else if (singingIndex == -1 && currentMs >= word.start.inMilliseconds) {
      singingIndex = i;
    }
  }
  return (sungCount: sungCount, singingIndex: singingIndex);
}

/// Builds the word `Wrap` for a karaoke line, skipping the rebuild when the
/// [_karaokeSignature] derived from [currentMs] hasn't changed since the
/// last frame — the active line's `SignalBuilder` reruns ~8 times/sec while
/// playing, but words only actually transition state a handful of times.
class _KaraokeLine extends StatefulWidget {
  final List<LyricWord> words;
  final int currentMs;
  final bool lineActive;
  final TextStyle style;

  const _KaraokeLine({
    required this.words,
    required this.currentMs,
    required this.lineActive,
    required this.style,
  });

  @override
  State<_KaraokeLine> createState() => _KaraokeLineState();
}

class _KaraokeLineState extends State<_KaraokeLine> {
  ({
    int sungCount,
    int singingIndex,
    bool lineActive,
    int wordsId,
    TextStyle style,
  })?
  _lastSignature;
  Widget? _lastBuilt;

  @override
  void didUpdateWidget(_KaraokeLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different lyrics source for the same track yields new `LyricWord`
    // objects with (possibly) identical timings. An unchanged signature
    // would keep serving the PREVIOUS provider's text until a word boundary
    // happened to invalidate the cache.
    if (!identical(oldWidget.words, widget.words)) {
      _lastSignature = null;
      _lastBuilt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final wordSignature = _karaokeSignature(widget.words, widget.currentMs);
    final signature = (
      sungCount: wordSignature.sungCount,
      singingIndex: wordSignature.singingIndex,
      lineActive: widget.lineActive,
      wordsId: identityHashCode(widget.words),
      style: widget.style,
    );
    final cached = _lastBuilt;
    if (cached != null && signature == _lastSignature) {
      return cached;
    }
    _lastSignature = signature;

    // Words arrive trimmed, so the gap is the space between them.
    final built = Wrap(
      spacing: (widget.style.fontSize ?? 30) * 0.24,
      children: [
        for (final word in widget.words)
          _KaraokeWordText(
            word: word,
            currentMs: widget.currentMs,
            lineActive: widget.lineActive,
            style: widget.style,
          ),
      ],
    );
    _lastBuilt = built;
    return built;
  }
}

class _KaraokeWordText extends StatelessWidget {
  final LyricWord word;
  final int currentMs;
  final bool lineActive;
  final TextStyle style;

  const _KaraokeWordText({
    required this.word,
    required this.currentMs,
    required this.lineActive,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final sung = lineActive && currentMs >= word.end.inMilliseconds;
    final singing =
        lineActive &&
        !sung &&
        currentMs >= word.start.inMilliseconds &&
        currentMs < word.end.inMilliseconds;
    // Dimmed only while its line is active and the word has not been reached.
    final pending = lineActive && !sung && !singing;
    final color = !lineActive
        ? style.color
        : (pending ? GColors.mutedForeground : GColors.foreground);

    return AnimatedDefaultTextStyle(
      // Two different transitions share this widget: not-yet-sung words dim
      // down as their line becomes active, which should ride the same slow
      // curve as the rest of the row, while a word lighting up mid-line has
      // to land on the beat.
      duration: pending ? _lyricTransitionDuration : _karaokeWordDuration,
      curve: pending ? _lyricTransitionCurve : Curves.linear,
      style: style.copyWith(color: color),
      child: Text(word.text),
    );
  }
}

/// Instrumental break: an empty gap that counts down with three dots during
/// its last five seconds.
class _LyricTimerWidget extends StatefulWidget {
  final LyricTimer item;
  final bool isActive;
  final double height;

  const _LyricTimerWidget({
    required this.item,
    required this.isActive,
    required this.height,
  });

  @override
  State<_LyricTimerWidget> createState() => _LyricTimerWidgetState();
}

class _LyricTimerWidgetState extends State<_LyricTimerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(_LyricTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) _syncPulse();
  }

  /// Only the active break can show its dots, so only it keeps a ticker.
  void _syncPulse() {
    if (widget.isActive) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return SizedBox(height: widget.height);

    return SizedBox(
      height: widget.height,
      child: SignalBuilder(
        builder: (context) {
          final progress = trackProgressSignal.value;
          final currentMs = progress.positionMs.toInt();
          final remainingMs =
              (widget.item.time.inMilliseconds +
                  widget.item.duration.inMilliseconds) -
              currentMs;
          final showDots = remainingMs > 0 && (remainingMs / 1000).ceil() <= 5;

          if (!showDots) return const SizedBox.shrink();

          return Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final dotValue = (remainingMs / 1000) - (2 - index);
                final active = dotValue > 0;

                return AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final pulse = active
                        ? (_pulseController.value * 0.15 + 1.0)
                        : 1.0;
                    return Transform.scale(scale: pulse, child: child);
                  },
                  child: AnimatedContainer(
                    duration: GDurations.medium,
                    margin: const EdgeInsets.only(right: 10),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: active ? GColors.foreground : GColors.foreground20,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}

class LyricsReaderDialog extends StatefulWidget {
  final String trackId;
  final String title;

  const LyricsReaderDialog({
    required this.trackId,
    required this.title,
    super.key,
  });

  static void show(BuildContext context, String trackId, String title) {
    unawaited(
      showGDialog<void>(
        context,
        builder: (context) =>
            LyricsReaderDialog(trackId: trackId, title: title),
      ),
    );
  }

  @override
  State<LyricsReaderDialog> createState() => _LyricsReaderDialogState();
}

class _LyricsReaderDialogState extends State<LyricsReaderDialog> {
  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final lyricsAsync = lyricsSignal(widget.trackId).value;
        return GDialog(
          title: widget.title,
          description: 'Текст песни',
          width: 560,
          content: lyricsAsync.map(
            data: (result) => _LyricsReaderBody(result: result),
            loading: () => _dialogFit(const GLoader()),
            error: (Object e, _) => _dialogFit(
              GEmptyState(
                icon: LucideIcons.circleAlert,
                title: 'Не удалось загрузить текст',
                message: e.toString(),
                compact: true,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Plain-text lyrics; instrumental breaks and blank lines become paragraph
/// gaps.
class _LyricsReaderBody extends StatelessWidget {
  final LyricsResult result;

  const _LyricsReaderBody({required this.result});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var paragraphBreak = false;
    for (final item in result.items) {
      if (item is! LyricLine || item.text.trim().isEmpty) {
        paragraphBreak = children.isNotEmpty;
        continue;
      }
      if (paragraphBreak) {
        children.add(const SizedBox(height: 20));
        paragraphBreak = false;
      }
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(item.text, style: GText.lg()),
        ),
      );
    }

    if (children.isEmpty) {
      return _dialogFit(
        const GEmptyState(
          icon: LucideIcons.micVocal,
          title: 'Текст отсутствует',
          message: 'Для этого трека текст не найден',
          compact: true,
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...children,
          if (result.providerName.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Источник: ${result.providerName}',
              style: GText.xs(color: GColors.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}
