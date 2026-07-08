// Smooths the recorder's raw RMS level into the silk-ribbon amplitude
// (PRD #103): an exponential moving average with a ~100ms time constant,
// mapped into the spec's amplitude window [0.10, 0.45]. Pure value math —
// the controller feeds it samples; the view reads `amplitude`.

import Foundation

struct LevelSmoother: Equatable {
    static let floor = 0.10
    static let ceiling = 0.45
    /// Speech RMS at the mic rarely exceeds ~0.25; this gain lets a normal
    /// speaking level span the whole amplitude window instead of hugging its
    /// bottom.
    static let gain = 4.0

    /// EMA time constant in seconds (~100ms per the spec).
    let timeConstant: Double
    private(set) var smoothed: Double = 0

    init(timeConstant: Double = 0.1) {
        self.timeConstant = timeConstant
    }

    /// Fold in one RMS sample taken `dt` seconds after the previous one,
    /// returning the updated amplitude. A non-positive `dt` adopts the sample
    /// outright rather than dividing by zero.
    @discardableResult
    mutating func add(rms: Double, dt: Double) -> Double {
        let sample = max(0, rms)
        let alpha = dt > 0 ? 1 - exp(-dt / timeConstant) : 1
        smoothed += (sample - smoothed) * alpha
        return amplitude
    }

    /// The ribbon amplitude for the current smoothed level, always inside
    /// [0.10, 0.45] — silence still leaves the ribbons faintly alive.
    var amplitude: Double {
        Self.floor + min(1, smoothed * Self.gain) * (Self.ceiling - Self.floor)
    }

    mutating func reset() {
        smoothed = 0
    }
}
