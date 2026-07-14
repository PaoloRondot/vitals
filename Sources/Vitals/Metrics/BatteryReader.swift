import Foundation
import IOKit

struct BatteryInfo {
    var percent: Int
    var isCharging: Bool
    var externalConnected: Bool
    var fullyCharged: Bool
    var watts: Double            // signed: + charging, - discharging
    var cycleCount: Int
    var healthPercent: Double?   // current max capacity vs design
    var temperature: Double?     // °C
    var timeRemainingMinutes: Int?
}

/// Battery state and health from the AppleSmartBattery registry entry.
final class BatteryReader {
    func read() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else { return nil }

        func int(_ key: String) -> Int? { props[key] as? Int }
        func bool(_ key: String) -> Bool { props[key] as? Bool ?? false }

        // On Apple Silicon CurrentCapacity is already a percentage.
        let percent = int("CurrentCapacity") ?? 0
        let amperage = int("Amperage") ?? 0 // mA, negative when discharging
        let voltage = int("Voltage") ?? 0   // mV
        let watts = Double(amperage) * Double(voltage) / 1_000_000

        var health: Double?
        if let design = int("DesignCapacity"), design > 0,
           let nominal = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity") {
            health = Double(nominal) / Double(design) * 100
        }

        let minutes = int("TimeRemaining").flatMap { $0 > 0 && $0 < 65535 ? $0 : nil }

        return BatteryInfo(percent: percent,
                           isCharging: bool("IsCharging"),
                           externalConnected: bool("ExternalConnected"),
                           fullyCharged: bool("FullyCharged"),
                           watts: watts,
                           cycleCount: int("CycleCount") ?? 0,
                           healthPercent: health,
                           temperature: int("Temperature").map { Double($0) / 100 },
                           timeRemainingMinutes: minutes)
    }
}
