use im::Vector;
use yandex_music::model::track::Track;

/// Cap on retained playback history. Unbounded growth + a full-vector clone
/// into the signal on every track advance leaks memory over long sessions.
/// 100 comfortably covers wave-seed needs (last 20 played).
const MAX_HISTORY_ENTRIES: usize = 100;

#[derive(Clone)]
pub struct HistoryState {
    pub entries: Vector<Track>,
}

impl HistoryState {
    pub fn empty() -> Self {
        Self {
            entries: Vector::new(),
        }
    }

    pub fn reset(&mut self) {
        self.entries = Vector::new();
    }

    /// Append a played track.
    ///
    /// Consecutive duplicates are collapsed: `RepeatMode::Single`, rapid
    /// skipping and re-adding the same track otherwise produced several
    /// identical entries, and `build_wave_history_seeds` then sent the same
    /// track up to 20 times as "history" to the Rotor recommender.
    pub fn push(&mut self, track: Track) {
        let len = self.entries.len();
        if len > 0 && self.entries.back().map(|t| &t.id) == Some(&track.id) {
            // Replace in place so a replayed track still refreshes the entry.
            self.entries.set(len - 1, track);
            return;
        }
        while self.entries.len() >= MAX_HISTORY_ENTRIES {
            self.entries.pop_front();
        }
        self.entries.push_back(track);
    }

    pub fn as_vector(&self) -> Vector<Track> {
        self.entries.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::util::track::test_track;

    #[test]
    fn push_caps_at_max_and_keeps_newest() {
        let mut h = HistoryState::empty();
        for i in 0..150 {
            h.push(test_track(&format!("t{i}")));
        }
        assert_eq!(h.entries.len(), 100);
        assert_eq!(h.entries.front().unwrap().id, "t50");
        assert_eq!(h.entries.back().unwrap().id, "t149");
    }

    #[test]
    fn reset_clears() {
        let mut h = HistoryState::empty();
        h.push(test_track("a"));
        h.reset();
        assert!(h.entries.is_empty());
    }
}
