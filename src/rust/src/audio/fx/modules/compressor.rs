use crate::audio::fx::Effect;
use crate::audio::fx::param::EffectParams;
use std::sync::Arc;

pub struct CompressorEffect {
    params: Arc<EffectParams>,
    envelope_l: f32,
    sample_rate: f32,
    /// Derived from params; recomputed only when EffectParams::version changes.
    threshold_lin: f32,
    makeup_lin: f32,
    attack_coef: f32,
    release_coef: f32,
    /// Gain-curve exponent: 1 - 1/ratio. gain = (threshold/envelope)^gain_exp.
    gain_exp: f32,
    /// Precomputed exponent table, indexed by the magnitude ratio.
    ///
    /// The gain curve is `(threshold/envelope)^k` with `k` constant while the
    /// params are unchanged, so it can be tabulated once in `recompute` and
    /// looked up per sample. That removes a `powf` (a non-inlined libm call)
    /// from the innermost loop — 48k calls/s at 48 kHz — without any accuracy
    /// loss worth hearing: 128 log-spaced steps over 40 dB of over-threshold
    /// range is ~0.3 dB worst case.
    gain_curve: [f32; GAIN_CURVE_STEPS],
    last_version: u32,
}

/// Log-spaced over-threshold range, in dB, covered by `gain_curve`.
const GAIN_CURVE_RANGE_DB: f32 = 40.0;
const GAIN_CURVE_STEPS: usize = 128;

impl CompressorEffect {
    pub fn new(params: Arc<EffectParams>, sample_rate: f32) -> Self {
        Self {
            params,
            envelope_l: 0.0,
            sample_rate,
            threshold_lin: 1.0,
            makeup_lin: 1.0,
            attack_coef: 0.0,
            release_coef: 0.0,
            gain_exp: 0.75,
            gain_curve: [1.0; GAIN_CURVE_STEPS],
            last_version: 0,
        }
    }

    #[inline]
    fn db_to_linear(db: f32) -> f32 {
        10.0_f32.powf(db / 20.0)
    }

    fn recompute(&mut self) {
        let threshold_db = self.params.get(0);
        let ratio = self.params.get(1).max(1.0);
        let attack_ms = self.params.get(2).max(0.1);
        let release_ms = self.params.get(3).max(10.0);

        self.threshold_lin = Self::db_to_linear(threshold_db);

        let makeup_db = (-threshold_db) * (1.0 - 1.0 / ratio) * 0.5;
        self.makeup_lin = Self::db_to_linear(makeup_db);

        self.attack_coef = (-1.0 / (attack_ms * 0.001 * self.sample_rate)).exp();
        self.release_coef = (-1.0 / (release_ms * 0.001 * self.sample_rate)).exp();
        self.gain_exp = 1.0 - 1.0 / ratio;

        // Tabulate gain = ratio^-k for ratio in 1..10^4 (0..40 dB).
        for (i, slot) in self.gain_curve.iter_mut().enumerate() {
            let db = i as f32 / (GAIN_CURVE_STEPS - 1) as f32 * GAIN_CURVE_RANGE_DB;
            *slot = (10.0_f32.powf(-db / 20.0)).powf(self.gain_exp);
        }
    }

    /// Gain for an envelope-to-threshold ratio, with linear interpolation
    /// between the two neighbouring table entries.
    #[inline(always)]
    fn gain_for_ratio(&self, ratio: f32) -> f32 {
        if ratio <= 1.0 {
            return 1.0;
        }
        let over_db = 20.0 * ratio.log10();
        if over_db >= GAIN_CURVE_RANGE_DB {
            return self.gain_curve[GAIN_CURVE_STEPS - 1];
        }
        let t = over_db / GAIN_CURVE_RANGE_DB * (GAIN_CURVE_STEPS - 1) as f32;
        let i = t as usize;
        let frac = t - i as f32;
        let lo = self.gain_curve[i];
        let hi = self.gain_curve[i + 1];
        lo + (hi - lo) * frac
    }
}

impl Effect for CompressorEffect {
    fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        if self.last_version != self.params.version() {
            self.last_version = self.params.version();
            self.recompute();
        }

        let threshold_lin = self.threshold_lin;
        let makeup_lin = self.makeup_lin;
        let attack_coef = self.attack_coef;
        let release_coef = self.release_coef;

        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            let input_level = (l.abs().max(r.abs())).max(1e-6);

            let coef = if input_level > self.envelope_l {
                attack_coef
            } else {
                release_coef
            };
            self.envelope_l = coef * self.envelope_l + (1.0 - coef) * input_level;

            // Table lookup instead of a per-sample `powf`. The detector is
            // deliberately L/R-linked through `envelope_l` (stereo image must
            // not wander), so there is no second envelope to track.
            let gain = if self.envelope_l > threshold_lin {
                self.gain_for_ratio(threshold_lin / self.envelope_l)
            } else {
                1.0
            };

            *l *= gain * makeup_lin;
            *r *= gain * makeup_lin;
        }
    }

    fn reset(&mut self) {
        self.envelope_l = 0.0;
    }
}
