import Foundation
import SensorShims

/// GPU clock and utilization from IOReport performance-state residencies.
final class GPUReader {
    private let available: Bool

    init() {
        available = vitals_gpu_init() == 1
    }

    /// Average active GPU clock (MHz) and busy fraction (0...1) since the
    /// last call. Nil on the first (priming) call and on failure.
    func read() -> (mhz: Double, busy: Double)? {
        guard available else { return nil }
        var mhz: Double = 0
        var busy: Double = 0
        guard vitals_gpu_sample(&mhz, &busy) == 1 else { return nil }
        return (mhz, busy)
    }
}
