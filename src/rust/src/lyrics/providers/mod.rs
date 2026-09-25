pub mod betterlyrics;
pub mod lrclib;
pub mod youlyplus;

use regex::Regex;
use std::sync::LazyLock;

static TITLE_CLEANUP_PATTERNS: LazyLock<Vec<Regex>> = LazyLock::new(|| {
    let patterns = [
        r"(?i)\s*\((?:[^)]*)(official|remaster|remix|live|acoustic|version|edit|extended|radio|clean|explicit|slowed|sped up|speed up|reverb|nightcore)(?:[^)]*)\)",
        r"(?i)\s*\[(?:[^\]]*)(official|remaster|remix|live|acoustic|version|edit|extended|radio|clean|explicit|slowed|sped up|speed up|reverb|nightcore)(?:[^\]]*)\]",
        r"\s*【.*?】",
        r"\s*\|.*$",
        r"(?i)\s*-\s*(official|slowed|sped up|speed up|reverb|nightcore|slowed\s*\+\s*reverb).*$",
        r"(?i)\s*\(feat\..*?\)",
        r"(?i)\s*\(ft\..*?\)",
        r"(?i)\s*feat\..*$",
        r"(?i)\s*ft\..*$",
    ];
    patterns.iter().map(|p| Regex::new(p).unwrap()).collect()
});

const ARTIST_SEPARATORS: &[&str] = &[
    " & ",
    " and ",
    ", ",
    " x ",
    " X ",
    " feat. ",
    " feat ",
    " ft. ",
    " ft ",
    " featuring ",
    " with ",
];

static ARTIST_SEPARATORS_LOWER: LazyLock<Vec<String>> =
    LazyLock::new(|| ARTIST_SEPARATORS.iter().map(|s| s.to_lowercase()).collect());

/// Inputs are truncated to this many chars before the distance is computed.
/// `levenshtein` is quadratic, and the strings come from a third-party HTTP
/// response, so an unbounded input is a remote OOM vector. Real artist/title
/// strings are far below this.
const MAX_LEVENSHTEIN_INPUT: usize = 512;

/// Strips common noise (`(Official Video)`, `feat. X`, ...) from a track title
/// so third-party lyrics providers can match it.
pub fn clean_title(title: &str) -> String {
    let mut cleaned = title.trim().to_string();
    for pattern in TITLE_CLEANUP_PATTERNS.iter() {
        cleaned = pattern.replace_all(&cleaned, "").to_string();
    }
    cleaned.trim().to_string()
}

/// Keeps only the primary artist, splitting on the first separator found
/// (`"A & B"` -> `"A"`).
pub fn clean_artist(artist: &str) -> String {
    let cleaned = artist.trim();
    let lowered: Vec<char> = cleaned.to_lowercase().chars().collect();
    for separator in ARTIST_SEPARATORS_LOWER.iter() {
        let sep: Vec<char> = separator.chars().collect();
        if let Some(pos) = find_subslice(&lowered, &sep) {
            // `pos` is a CHAR index into the lowercased string, which is what
            // we need: `to_lowercase` only ever expands, so counting chars up
            // to the match gives a valid boundary in the original. (The old
            // byte-offset-then-char-count version over-shot whenever an
            // expansion happened before the separator, leaking the separator
            // into the artist name sent to every provider.)
            let cut: String = cleaned.chars().take(pos).collect();
            return cut.trim().to_string();
        }
    }
    cleaned.to_string()
}

/// Index of the first occurrence of `needle` in `haystack`, both char slices.
fn find_subslice(haystack: &[char], needle: &[char]) -> Option<usize> {
    if needle.is_empty() || haystack.len() < needle.len() {
        return None;
    }
    (0..=haystack.len() - needle.len()).find(|&i| &haystack[i..i + needle.len()] == needle)
}

pub fn levenshtein(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.chars().take(MAX_LEVENSHTEIN_INPUT).collect();
    let b: Vec<char> = b.chars().take(MAX_LEVENSHTEIN_INPUT).collect();
    let (len1, len2) = (a.len(), b.len());

    // Two rolling rows instead of the full (len1+1)*(len2+1) matrix. The
    // provider is fed strings straight from a third-party HTTP response with
    // no length cap, and the matrix was `n*m*8` bytes of live allocation on
    // the async runtime — a few tens of kB of input meant hundreds of MB.
    let mut prev: Vec<usize> = (0..=len2).collect();
    let mut cur: Vec<usize> = vec![0; len2 + 1];

    for i in 1..=len1 {
        cur[0] = i;
        for j in 1..=len2 {
            let cost = usize::from(a[i - 1] != b[j - 1]);
            cur[j] = (prev[j] + 1).min(cur[j - 1] + 1).min(prev[j - 1] + cost);
        }
        std::mem::swap(&mut prev, &mut cur);
    }

    prev[len2]
}

/// Fuzzy 0.0-1.0 similarity score used to rank third-party search results
/// against the requested title/artist.
pub fn string_similarity(a: &str, b: &str) -> f64 {
    let a = a.trim().to_lowercase();
    let b = b.trim().to_lowercase();
    if a == b {
        return 1.0;
    }
    if a.is_empty() || b.is_empty() {
        return 0.0;
    }
    if a.contains(&b) || b.contains(&a) {
        return 0.8;
    }
    let max_len = a.chars().count().max(b.chars().count());
    let distance = levenshtein(&a, &b);
    1.0 - (distance as f64 / max_len as f64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clean_title_strips_official_video_tag() {
        assert_eq!(clean_title("Song Name (Official Video)"), "Song Name");
    }

    #[test]
    fn clean_title_strips_feat_suffix() {
        assert_eq!(clean_title("Song Name feat. Someone"), "Song Name");
    }

    #[test]
    fn clean_title_leaves_plain_title_untouched() {
        assert_eq!(clean_title("Plain Song Title"), "Plain Song Title");
    }

    #[test]
    fn clean_artist_keeps_only_primary_artist() {
        assert_eq!(clean_artist("Artist A & Artist B"), "Artist A");
        assert_eq!(clean_artist("Artist A, Artist B"), "Artist A");
        assert_eq!(clean_artist("Artist A feat. Artist B"), "Artist A");
    }

    #[test]
    fn clean_artist_leaves_single_artist_untouched() {
        assert_eq!(clean_artist("Solo Artist"), "Solo Artist");
    }

    #[test]
    fn clean_artist_handles_case_insensitive_separator() {
        assert_eq!(clean_artist("Artist A FEAT. Artist B"), "Artist A");
    }

    #[test]
    fn clean_artist_does_not_panic_on_multibyte_lowercase_expansion() {
        // 'İ' (U+0130) lowercases to a 2-char / 3-byte sequence ("i̇"), so the
        // byte offset found in the lowercased haystack no longer lines up
        // with a char boundary in the original string unless converted to a
        // char count first.
        let artist = "İstanbul & Ankara";
        assert_eq!(clean_artist(artist), "İstanbul");
    }

    #[test]
    fn levenshtein_distance_matches_known_values() {
        assert_eq!(levenshtein("kitten", "sitting"), 3);
        assert_eq!(levenshtein("same", "same"), 0);
        assert_eq!(levenshtein("", "abc"), 3);
    }

    #[test]
    fn string_similarity_exact_match_is_one() {
        assert_eq!(string_similarity("Song Title", "song title"), 1.0);
    }

    #[test]
    fn string_similarity_substring_match_is_high() {
        assert_eq!(string_similarity("Song", "Song (Remastered)"), 0.8);
    }

    #[test]
    fn string_similarity_empty_input_is_zero() {
        assert_eq!(string_similarity("", "Song"), 0.0);
        assert_eq!(string_similarity("Song", ""), 0.0);
    }

    #[test]
    fn string_similarity_unrelated_strings_is_low() {
        assert!(string_similarity("Completely Different", "Nothing Alike") < 0.5);
    }
}
