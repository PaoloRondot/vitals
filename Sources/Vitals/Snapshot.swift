import Foundation

struct Snapshot {
    var cpuLoad: Double = 0            // 0...1, all cores aggregated
    var perCoreLoad: [Double] = []     // 0...1 each
    var cpuTemp: Double?               // °C, nil if sensors unavailable
    var eCoreMHz: Double?              // avg active E-cluster clock
    var pCoreMHz: Double?              // avg active P-cluster clock

    /// Headline clock: the P cluster (what "CPU speed" means colloquially),
    /// falling back to the E cluster on hypothetical P-less hardware.
    var cpuGHz: Double? {
        if let p = pCoreMHz, p > 0 { return p / 1000 }
        if let e = eCoreMHz, e > 0 { return e / 1000 }
        return nil
    }

    var ramUsed: UInt64 = 0            // bytes
    var ramTotal: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0

    var netDown: Double = 0            // bytes/s
    var netUp: Double = 0

    var fanRPMs: [Double] = []
    var powerWatts: Double?

    var memoryPressureLevel: Int = 1  // kernel level: 1 normal, 2 warning, 4 critical
    var latencyMs: Double?            // TCP connect RTT to 1.1.1.1
    var latencyFailed: Bool = false   // probe ran and could not connect

    var ramFraction: Double {
        ramTotal > 0 ? Double(ramUsed) / Double(ramTotal) : 0
    }
}

enum Format {
    static func bytes(_ value: UInt64) -> String {
        let gb = Double(value) / 1_073_741_824
        if gb >= 10 { return String(format: "%.0fG", gb) }
        if gb >= 1 { return String(format: "%.1fG", gb) }
        return String(format: "%.0fM", Double(value) / 1_048_576)
    }

    static func bytesLong(_ value: UInt64) -> String {
        let gb = Double(value) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(value) / 1_048_576)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let v = max(bytesPerSecond, 0)
        if v >= 1_048_576 { return String(format: "%.1f MB/s", v / 1_048_576) }
        if v >= 1_024 { return String(format: "%.0f KB/s", v / 1_024) }
        return String(format: "%.0f B/s", v)
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }

    static func temperature(_ celsius: Double) -> String {
        String(format: "%.0f°", celsius)
    }
}
