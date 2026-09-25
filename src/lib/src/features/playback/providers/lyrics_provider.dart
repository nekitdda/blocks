import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/core/services/rust_bridge.dart';
import 'package:youmuz/src/rust/api/content.dart';
import 'package:youmuz/src/rust/api/models.dart';

sealed class LyricItem {
  final Duration time;
  LyricItem(this.time);
}

class LyricWord {
  final String text;
  final Duration start;
  final Duration end;
  LyricWord({required this.text, required this.start, required this.end});
}

class LyricLine extends LyricItem {
  final String text;
  final Duration duration;
  final List<LyricWord>? words;
  LyricLine(super.time, this.text, this.duration, {this.words});
}

class LyricTimer extends LyricItem {
  final Duration duration;
  LyricTimer(super.time, this.duration);
}

/// A track's parsed lyrics plus the name of the source that provided them,
/// so the UI can show where the text came from.
class LyricsResult {
  final List<LyricItem> items;
  final String providerName;
  LyricsResult(this.items, this.providerName);
}

/// Insertion-ordered so the oldest entry is always `keys.first`.
///
/// Bounded: each value holds a fully parsed word-level timeline (kilobytes per
/// track, not tens of bytes), and the map was never evicted — it grew for the
/// lifetime of the process as the user browsed.
final Map<String, FutureSignal<LyricsResult>> _lyricsCache = {};
const int _lyricsCacheLimit = 20;

/// Drops every cached lyrics fetch so the next [lyricsSignal] read refetches
/// from Rust. Call this when the set of enabled lyrics providers changes —
/// otherwise a track's lyrics stay pinned to whatever source answered
/// before the toggle, even after a source is disabled.
void clearLyricsCache() {
  _lyricsCache.clear();
}

FutureSignal<LyricsResult> lyricsSignal(String trackId) {
  final existing = _lyricsCache[trackId];
  if (existing != null) {
    // Refresh recency so the hot track is not the one evicted.
    _lyricsCache.remove(trackId);
    _lyricsCache[trackId] = existing;
    return existing;
  }
  final created = futureSignal<LyricsResult>(() async {
    final result = await runRustFetch(
      (ctx) => getLyrics(ctx: ctx, trackId: trackId),
    );
    if (result == null) return LyricsResult([], '');
    return LyricsResult(_toLyricItems(result.lines), result.providerName);
  });
  _lyricsCache[trackId] = created;
  while (_lyricsCache.length > _lyricsCacheLimit) {
    _lyricsCache.remove(_lyricsCache.keys.first);
  }
  return created;
}

List<LyricItem> _toLyricItems(List<LyricsLineDto> lines) {
  if (lines.isEmpty) return [];

  final rawLines = lines
      .map(
        (line) => (
          time: Duration(milliseconds: line.startMs),
          text: line.text,
          words: line.words.isEmpty
              ? null
              : line.words
                    .map(
                      (w) => LyricWord(
                        text: w.text,
                        start: Duration(milliseconds: w.startMs),
                        end: Duration(milliseconds: w.endMs),
                      ),
                    )
                    .toList(),
        ),
      )
      .toList();

  final result = <LyricItem>[];

  if (rawLines.isNotEmpty && rawLines.first.time > const Duration(seconds: 5)) {
    result.add(
      LyricTimer(
        const Duration(seconds: 1),
        rawLines.first.time - const Duration(seconds: 2),
      ),
    );
  }

  for (var i = 0; i < rawLines.length; i++) {
    final current = rawLines[i];
    final nextTime = (i + 1 < rawLines.length)
        ? rawLines[i + 1].time
        : current.time + const Duration(seconds: 10);

    final duration = nextTime - current.time;

    if (duration > const Duration(seconds: 7)) {
      const textDuration = Duration(seconds: 4);
      result.add(
        LyricLine(
          current.time,
          current.text,
          textDuration,
          words: current.words,
        ),
      );

      final timerStart = current.time + textDuration;
      final timerDuration =
          duration - textDuration - const Duration(seconds: 1);

      result.add(LyricTimer(timerStart, timerDuration));
    } else {
      result.add(
        LyricLine(current.time, current.text, duration, words: current.words),
      );
    }
  }

  return result;
}
