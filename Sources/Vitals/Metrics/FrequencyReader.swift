import Foundation
import SensorShims

/// Live CPU clocks from IOReport performance-state residency deltas.
final class FrequencyReader {
    private let available: Bool

    init() {
        available = vitals_freq_init() == 1
        if !available, ProcessInfo.processInfo.environment["VITALS_DEBUG"] != nil {
            FileHandle.standardError.write(Data("[vitals] CPU frequency source unavailable\n".utf8))
        }
    }

    /// Average active frequency of the E and P clusters in MHz since the last
    /// call. Returns nil on the first (priming) call and on failure.
    func read() -> (eMHz: Double, pMHz: Double)? {
        guard available else { return nil }
        var e: Double = 0
        var p: Double = 0
        guard vitals_freq_sample(&e, &p) == 1 else { return nil }
        return (e, p)
    }
}
