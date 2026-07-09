// Maps the recorder's raw RMS level onto the silk-ribbon amplitude (PRD
// #103), perceptually: RMS → dBFS, the speech window [-50, -26] dB → [0, 1]
// through a smoothstep, then a fast-attack / slow-release envelope so
// syllable onsets snap the ribbon up and the gaps between words let it fall
// away gently. Pure value math — the controller feeds it samples; the view
// reads `amplitude`.

import Foundation

struct LevelSmoother: Equatable {
    static let floor = 0.10
    static let ceiling = 0.45
    /// The dBFS window speech at a Mac mic actually occupies: room noise
    /// (RMS ~0.003) sits at the bottom, and the top is the calibrated
    /// close-mic syllable level (RMS ~0.05) — not shouting — so a normal
    /// voice actually reaches the ceiling. A -18 dB top left real voices
    /// peaking around 0.31 of [0.10, 0.45]: the ribbon reacted, but small.
    static let dbSilence = -50.0
    static let dbLoud = -26.0

    /// Envelope time constants in seconds: attack fast enough that a
    /// syllable onset registers within a frame or two, release slow enough
    /// that decays trail instead of flickering.
    let attack: Double
    let release: Double
    private(set) var envelope: Double = 0

    init(attack: Double = 0.05, release: Double = 0.25) {
        self.attack = attack
        self.release = release
    }

    /// Fold in one RMS sample taken `dt` seconds after the previous one,
    /// returning the updated amplitude. A non-positive `dt` adopts the
    /// sample outright rather than dividing by zero.
    @discardableResult
    mutating func add(rms: Double, dt: Double) -> Double {
        let db = 20 * log10(max(rms, 1e-6))
        let linear = min(1, max(0, (db - Self.dbSilence) / (Self.dbLoud - Self.dbSilence)))
        // Smoothstep expands the contrast the eye actually reads: syllables
        // in the window's upper half get pushed toward the ceiling while the
        // between-word residue (~-46 dB) gets pressed toward the floor,
        // nearly doubling the visible talk→gap swing.
        let loudness = linear * linear * (3 - 2 * linear)
        let timeConstant = loudness > envelope ? attack : release
        let alpha = dt > 0 ? 1 - exp(-dt / timeConstant) : 1
        envelope += (loudness - envelope) * alpha
        return amplitude
    }

    /// The ribbon amplitude for the current envelope, always inside
    /// [0.10, 0.45] — silence still leaves the ribbons faintly alive.
    var amplitude: Double {
        Self.floor + envelope * (Self.ceiling - Self.floor)
    }

    mutating func reset() {
        envelope = 0
    }
}
