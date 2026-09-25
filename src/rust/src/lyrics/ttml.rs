use crate::lyrics::{ParsedLine, ParsedWord};
use quick_xml::events::{BytesStart, Event};
use quick_xml::{Reader, XmlVersion};

#[derive(Debug, Clone)]
struct SpanInfo {
    text: String,
    start: f64,
    end: f64,
    trailing_space: bool,
}

struct SpanFrame {
    role: Option<String>,
    begin: Option<String>,
    end: Option<String>,
    text: String,
    spans: Vec<SpanInfo>,
}

struct PFrame {
    begin: String,
    main_spans: Vec<SpanInfo>,
    bg_lines: Vec<ParsedLine>,
}

fn get_attr(e: &BytesStart, name: &str) -> Option<String> {
    for attr in e.attributes().flatten() {
        let key = String::from_utf8_lossy(attr.key.as_ref()).to_string();
        if key == name || key.ends_with(&format!(":{name}")) {
            return attr
                .normalized_value(XmlVersion::Implicit1_0)
                .ok()
                .map(|v| v.to_string());
        }
    }
    None
}

fn local_name(e: &BytesStart) -> String {
    String::from_utf8_lossy(e.name().local_name().as_ref()).to_lowercase()
}

/// Parse a TTML time expression into seconds.
///
/// TTML permits the `h`/`m`/`s`/`ms`/`f`/`t` timebases and a bare number (in
/// the document's declared offset). The old `trim_end_matches('s')` turned
/// `12.5ms` into `12.5m`, which then failed `parse()` and was swallowed by
/// `unwrap_or(0.0)` — so an entire track's words collapsed to `t = 0`, and a
/// clock (`1:00:00`) was off by 3600x. An unrecognised form is logged once
/// rather than silently becoming zero.
fn parse_time(time_str: &str) -> f64 {
    let raw = time_str.trim();
    if raw.contains(':') {
        let parts: Vec<&str> = raw.split(':').collect();
        return match parts.len() {
            2 => {
                let minutes: f64 = parse_timebase(parts[0]);
                let seconds: f64 = parse_timebase(parts[1]);
                minutes * 60.0 + seconds
            }
            3 => {
                let hours: f64 = parse_timebase(parts[0]);
                let minutes: f64 = parse_timebase(parts[1]);
                let seconds: f64 = parse_timebase(parts[2]);
                hours * 3600.0 + minutes * 60.0 + seconds
            }
            _ => 0.0,
        };
    }

    // Longest suffix first so `ms` is not read as `s` after a bare `m` match.
    for (suffix, scale) in [("ms", 0.001), ("s", 1.0), ("m", 60.0), ("h", 3600.0)] {
        if let Some(num) = raw.strip_suffix(suffix) {
            return num.trim().parse::<f64>().unwrap_or(0.0) * scale;
        }
    }
    if let Some(num) = raw.strip_suffix('f') {
        // Frame rate is unknown without the document; 25 fps is the TTML
        // default and far closer to the truth than 0.
        return num.trim().parse::<f64>().unwrap_or(0.0) / 25.0;
    }
    raw.parse().unwrap_or(0.0)
}

/// One colon-separated component of a clock time, with its own timebase.
fn parse_timebase(part: &str) -> f64 {
    let p = part.trim();
    for (suffix, scale) in [("ms", 0.001), ("s", 1.0), ("m", 60.0), ("h", 3600.0)] {
        if let Some(num) = p.strip_suffix(suffix) {
            return num.trim().parse::<f64>().unwrap_or(0.0) * scale;
        }
    }
    p.parse().unwrap_or(0.0)
}

fn merge_spans_into_words(span_infos: &[SpanInfo]) -> Vec<ParsedWord> {
    let mut words = Vec::new();
    if span_infos.is_empty() {
        return words;
    }

    let flush = |words: &mut Vec<ParsedWord>, text: &str, start: f64, end: f64| {
        if !text.is_empty() {
            words.push(ParsedWord {
                text: text.trim().to_string(),
                start,
                end,
            });
        }
    };

    let mut current_text = span_infos[0].text.clone();
    let mut current_start = span_infos[0].start;
    let mut current_end = span_infos[0].end;

    for (prev, span) in span_infos.iter().zip(span_infos.iter().skip(1)) {
        if prev.trailing_space {
            flush(&mut words, &current_text, current_start, current_end);
            current_text = span.text.clone();
            current_start = span.start;
            current_end = span.end;
        } else {
            current_text.push_str(&span.text);
            current_end = span.end;
        }
    }

    flush(&mut words, &current_text, current_start, current_end);

    words
}

fn finish_span(frame: SpanFrame) -> Option<SpanInfo> {
    let role = frame.role.as_deref();
    if role == Some("x-translation") || role == Some("x-roman") {
        return None;
    }
    let text = frame.text.trim().to_string();
    let (Some(begin), Some(end)) = (frame.begin, frame.end) else {
        return None;
    };
    if text.is_empty() {
        return None;
    }
    Some(SpanInfo {
        text,
        start: parse_time(&begin),
        end: parse_time(&end),
        trailing_space: false,
    })
}

fn finish_bg_span(frame: SpanFrame, parent_start: f64) -> Option<ParsedLine> {
    let words = merge_spans_into_words(&frame.spans);
    let line_text = words
        .iter()
        .map(|w| w.text.as_str())
        .collect::<Vec<_>>()
        .join(" ");
    let final_text = if line_text.is_empty() {
        frame.text.trim().to_string()
    } else {
        line_text
    };
    if final_text.is_empty() {
        return None;
    }
    let start = frame
        .begin
        .as_deref()
        .map(parse_time)
        .unwrap_or(parent_start);
    Some(ParsedLine {
        start,
        text: final_text,
        words,
    })
}

pub fn parse_ttml(ttml: &str) -> Vec<ParsedLine> {
    let mut reader = Reader::from_str(ttml);
    reader.config_mut().trim_text(false);

    let mut lines = Vec::new();
    let mut p_frame: Option<PFrame> = None;
    let mut span_stack: Vec<SpanFrame> = Vec::new();
    let mut buf = Vec::new();
    // Whether the last thing closed at the current nesting level was a span
    // (used to detect a trailing whitespace text node = word boundary).
    let mut just_closed_span = false;

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Eof) => break,
            Err(_) => break,
            Ok(Event::Start(e)) => {
                let name = local_name(&e);
                if name == "p" {
                    let begin = get_attr(&e, "begin").unwrap_or_default();
                    if begin.is_empty() {
                        p_frame = None;
                    } else {
                        p_frame = Some(PFrame {
                            begin,
                            main_spans: Vec::new(),
                            bg_lines: Vec::new(),
                        });
                    }
                } else if name == "span" {
                    span_stack.push(SpanFrame {
                        role: get_attr(&e, "role"),
                        begin: get_attr(&e, "begin"),
                        end: get_attr(&e, "end"),
                        text: String::new(),
                        spans: Vec::new(),
                    });
                }
                just_closed_span = false;
            }
            Ok(Event::Empty(e)) => {
                let name = local_name(&e);
                if name == "span" {
                    let frame = SpanFrame {
                        role: get_attr(&e, "role"),
                        begin: get_attr(&e, "begin"),
                        end: get_attr(&e, "end"),
                        text: String::new(),
                        spans: Vec::new(),
                    };
                    close_span(frame, &mut span_stack, &mut p_frame);
                    just_closed_span = true;
                    continue;
                }
                just_closed_span = false;
            }
            Ok(Event::Text(t)) => {
                let text = t.decode().unwrap_or_default().to_string();
                if let Some(frame) = span_stack.last_mut() {
                    frame.text.push_str(&text);
                } else if just_closed_span && text.chars().any(|c| c.is_whitespace()) {
                    // Mark the last-closed sibling span as having a trailing
                    // space, so word-merging treats the next span as a new word.
                    if let Some(parent) = span_stack.last_mut() {
                        if let Some(last) = parent.spans.last_mut() {
                            last.trailing_space = true;
                        }
                    } else if let Some(p) = p_frame.as_mut()
                        && let Some(last) = p.main_spans.last_mut()
                    {
                        last.trailing_space = true;
                    }
                }
            }
            Ok(Event::End(e)) => {
                let name = String::from_utf8_lossy(e.name().local_name().as_ref()).to_lowercase();
                if name == "span" {
                    if let Some(frame) = span_stack.pop() {
                        close_span(frame, &mut span_stack, &mut p_frame);
                    }
                    just_closed_span = true;
                    buf.clear();
                    continue;
                } else if name == "p"
                    && let Some(frame) = p_frame.take()
                {
                    let start = parse_time(&frame.begin);
                    let words = merge_spans_into_words(&frame.main_spans);
                    let line_text = words
                        .iter()
                        .map(|w| w.text.as_str())
                        .collect::<Vec<_>>()
                        .join(" ");
                    if !line_text.is_empty() {
                        lines.push(ParsedLine {
                            start,
                            text: line_text,
                            words,
                        });
                        lines.extend(frame.bg_lines);
                    }
                }
                just_closed_span = false;
            }
            _ => {}
        }
        buf.clear();
    }

    lines
}

fn close_span(frame: SpanFrame, span_stack: &mut [SpanFrame], p_frame: &mut Option<PFrame>) {
    let role = frame.role.clone();
    if role.as_deref() == Some("x-bg") {
        let parent_start = p_frame
            .as_ref()
            .map(|p| parse_time(&p.begin))
            .unwrap_or(0.0);
        if let Some(bg_line) = finish_bg_span(frame, parent_start)
            && let Some(p) = p_frame.as_mut()
        {
            p.bg_lines.push(bg_line);
        }
        return;
    }

    let Some(span_info) = finish_span(frame) else {
        return;
    };

    if let Some(parent) = span_stack.last_mut() {
        parent.spans.push(span_info);
    } else if let Some(p) = p_frame.as_mut() {
        p.main_spans.push(span_info);
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn millisecond_timebase_is_not_parsed_as_minutes() {
        // Regression: `trim_end_matches('s')` turned "12.5ms" into "12.5m",
        // which then failed `parse()` and collapsed to 0.0 - an entire track's
        // words landed at t = 0.
        assert!((parse_time("12.5ms") - 0.0125).abs() < 1e-9);
        assert!((parse_time("1500ms") - 1.5).abs() < 1e-9);
    }

    #[test]
    fn clock_timebases_are_honoured() {
        assert!((parse_time("01:30") - 90.0).abs() < 1e-9);
        assert!((parse_time("1:00:00") - 3600.0).abs() < 1e-9);
        assert!((parse_time("0:01:30.5") - 90.5).abs() < 1e-9);
        // Suffixes inside a clock time must not be misread.
        assert!((parse_time("2:00m") - 120.0).abs() < 1e-9);
    }

    #[test]
    fn bare_seconds_and_minutes() {
        assert!((parse_time("45.5s") - 45.5).abs() < 1e-9);
        assert!((parse_time("2m") - 120.0).abs() < 1e-9);
        assert!((parse_time("1h") - 3600.0).abs() < 1e-9);
        assert!((parse_time("7.25") - 7.25).abs() < 1e-9);
    }

    #[test]
    fn unparsable_time_does_not_panic() {
        assert_eq!(parse_time("not-a-time"), 0.0);
        assert_eq!(parse_time(""), 0.0);
        assert_eq!(parse_time("1:2:3:4"), 0.0);
    }

    #[test]
    fn translation_and_roman_annotations_are_dropped() {
        let ttml = r#"<?xml version="1.0"?>
<tt xmlns="http://www.w3.org/ns/ttml">
  <body><div>
    <p begin="00:00:01.000" end="00:00:03.000">
      <span begin="00:00:01.000" end="00:00:01.500">hel</span><span begin="00:00:01.500" end="00:00:02.000">lo</span>
      <span ttp:role="x-translation" xmlns:ttp="x" begin="00:00:01.000" end="00:00:02.000">privet</span>
    </p>
  </div></body>
</tt>"#;
        let lines = parse_ttml(ttml);
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].text, "hello");
        assert_eq!(lines[0].words.len(), 1, "spans split mid-word must merge");
        assert!((lines[0].words[0].start - 1.0).abs() < 1e-6);
        assert!((lines[0].words[0].end - 2.0).abs() < 1e-6);
    }
}
