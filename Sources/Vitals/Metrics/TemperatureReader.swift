import Foundation
import SensorShims

/// CPU die temperature via the AppleVendor HID temperature sensors.
///
/// Sensor naming varies across chip generations, so we enumerate everything
/// once and pick CPU-looking sensors by name, with progressively looser
/// filters. Run with VITALS_DEBUG=1 to dump every sensor name and reading.
final class TemperatureReader {
    private let sensorIndices: [Int32]
    private let debug = ProcessInfo.processInfo.environment["VITALS_DEBUG"] != nil

    init() {
        let count = vitals_temp_init()
        guard count > 0 else {
            if ProcessInfo.processInfo.environment["VITALS_DEBUG"] != nil {
                FileHandle.standardError.write(Data("[vitals] no HID temperature sensors found (count=\(count))\n".utf8))
            }
            sensorIndices = []
            return
        }

        var names: [String] = []
        for index in 0..<count {
            var buf = [CChar](repeating: 0, count: 256)
            _ = vitals_temp_name(index, &buf, 256)
            let utf8 = buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
            names.append(String(decoding: utf8, as: UTF8.self))
        }

        if ProcessInfo.processInfo.environment["VITALS_DEBUG"] != nil {
            for (index, name) in names.enumerated() {
                let value = vitals_temp_read(Int32(index))
                FileHandle.standardError.write(Data(String(format: "[vitals] sensor %02d: %-40s %.1f°C\n", index, (name as NSString).utf8String!, value).utf8))
            }
        }

        let lowered = names.map { $0.lowercased() }
        // Die sensors first ("PMU tdie…"), then performance/efficiency
        // cluster sensors ("pACC…"/"eACC…"), then anything CPU-flavored.
        var picked = lowered.indices.filter { lowered[$0].contains("tdie") }
        if picked.isEmpty {
            picked = lowered.indices.filter { lowered[$0].hasPrefix("pacc") || lowered[$0].hasPrefix("eacc") }
        }
        if picked.isEmpty {
            picked = lowered.indices.filter { lowered[$0].contains("cpu") || lowered[$0].contains("soc") }
        }
        sensorIndices = picked.map(Int32.init)
    }

    /// Hottest CPU sensor in °C, or nil if unavailable.
    func read() -> Double? {
        var maxTemp: Double?
        for index in sensorIndices {
            let value = vitals_temp_read(index)
            // Discard NaN and implausible readings.
            guard value.isFinite, value > 1, value < 130 else { continue }
            maxTemp = max(maxTemp ?? -.infinity, value)
        }
        return maxTemp
    }
}
