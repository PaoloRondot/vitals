import Foundation
import IOKit
import SensorShims

/// Minimal AppleSMC user-client for reading keys (fans, power).
final class SMCClient {
    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return nil
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    private func call(_ input: inout VitalsSMCKeyData) -> VitalsSMCKeyData? {
        var output = VitalsSMCKeyData()
        var outputSize = MemoryLayout<VitalsSMCKeyData>.stride
        let result = IOConnectCallStructMethod(connection,
                                               UInt32(VITALS_SMC_SELECTOR_HANDLE_EVENT),
                                               &input,
                                               MemoryLayout<VitalsSMCKeyData>.stride,
                                               &output,
                                               &outputSize)
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    private static func fourCC(_ key: String) -> UInt32? {
        let scalars = Array(key.unicodeScalars)
        guard scalars.count == 4, scalars.allSatisfy({ $0.isASCII }) else { return nil }
        return scalars.reduce(UInt32(0)) { ($0 << 8) | UInt32($1.value) }
    }

    /// Key metadata: byte size, four-char type, attribute flags.
    func keyInfo(_ key: String) -> (size: Int, type: String, attributes: UInt8)? {
        guard let keyCode = Self.fourCC(key) else { return nil }
        var request = VitalsSMCKeyData()
        request.key = keyCode
        request.data8 = UInt8(VITALS_SMC_CMD_GET_KEY_INFO)
        guard let info = call(&request) else { return nil }
        return (Int(info.keyInfo.dataSize), Self.typeName(info.keyInfo.dataType), info.keyInfo.dataAttributes)
    }

    /// Read a key and decode it to a Double based on its SMC data type.
    func read(_ key: String) -> Double? {
        guard let keyCode = Self.fourCC(key) else { return nil }

        var infoRequest = VitalsSMCKeyData()
        infoRequest.key = keyCode
        infoRequest.data8 = UInt8(VITALS_SMC_CMD_GET_KEY_INFO)
        guard let info = call(&infoRequest) else { return nil }

        var readRequest = VitalsSMCKeyData()
        readRequest.key = keyCode
        readRequest.keyInfo.dataSize = info.keyInfo.dataSize
        readRequest.data8 = UInt8(VITALS_SMC_CMD_READ_KEY)
        guard let response = call(&readRequest) else { return nil }

        let size = Int(info.keyInfo.dataSize)
        let bytes = withUnsafeBytes(of: response.bytes) { Array($0.prefix(size)) }
        return Self.decode(type: info.keyInfo.dataType, bytes: bytes)
    }

    private static func typeName(_ type: UInt32) -> String {
        String(bytes: [UInt8((type >> 24) & 0xff), UInt8((type >> 16) & 0xff),
                       UInt8((type >> 8) & 0xff), UInt8(type & 0xff)],
               encoding: .ascii) ?? ""
    }

    /// Write a numeric value to a key, encoded per the key's SMC data type.
    /// Requires root; returns false otherwise (or for unsupported types).
    @discardableResult
    func write(_ key: String, value: Double) -> Bool {
        guard let keyCode = Self.fourCC(key) else { return false }

        var infoRequest = VitalsSMCKeyData()
        infoRequest.key = keyCode
        infoRequest.data8 = UInt8(VITALS_SMC_CMD_GET_KEY_INFO)
        guard let info = call(&infoRequest) else { return false }

        var writeRequest = VitalsSMCKeyData()
        writeRequest.key = keyCode
        writeRequest.keyInfo.dataSize = info.keyInfo.dataSize
        writeRequest.data8 = UInt8(VITALS_SMC_CMD_WRITE_KEY)
        let encoded = withUnsafeMutableBytes(of: &writeRequest.bytes) { buffer -> Bool in
            switch Self.typeName(info.keyInfo.dataType) {
            case "flt ":
                let raw = Float(value).bitPattern.littleEndian
                buffer[0] = UInt8(raw & 0xff)
                buffer[1] = UInt8((raw >> 8) & 0xff)
                buffer[2] = UInt8((raw >> 16) & 0xff)
                buffer[3] = UInt8((raw >> 24) & 0xff)
                return true
            case "ui8 ":
                buffer[0] = UInt8(max(0, min(255, value)))
                return true
            default:
                return false
            }
        }
        guard encoded else { return false }
        return call(&writeRequest) != nil
    }

    private static func decode(type: UInt32, bytes: [UInt8]) -> Double? {
        switch typeName(type) {
        case "flt ": // little-endian IEEE float (Apple Silicon)
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: raw))
        case "ui8 ", "si8 ":
            guard let b = bytes.first else { return nil }
            return Double(b)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double((UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3]))
        case "fpe2": // big-endian fixed point, 2 fractional bits (Intel fans)
            guard bytes.count >= 2 else { return nil }
            return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1])) / 4.0
        case "sp78": // big-endian signed fixed point, 8 fractional bits (Intel temps)
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return Double(raw) / 256.0
        default:
            return nil
        }
    }

    // MARK: - Higher-level readings

    var fanCount: Int {
        guard let count = read("FNum"), count > 0, count < 10 else { return 0 }
        return Int(count)
    }

    func fanSpeeds() -> [Double] {
        (0..<fanCount).compactMap { read("F\($0)Ac") }
    }

    /// Manufacturer RPM bounds of fan 0 — the safe manual range.
    func fanLimits() -> (min: Double, max: Double)? {
        guard let min = read("F0Mn"), let max = read("F0Mx"), max > min else { return nil }
        return (min, max)
    }

    /// True when fans are in forced (manual target) mode.
    func fansForced() -> Bool {
        (read("F0Md") ?? 0) > 0
    }

    /// Force all fans to a target RPM. Root only.
    func setFans(targetRPM: Double) -> Bool {
        var ok = fanCount > 0
        for i in 0..<fanCount {
            ok = write("F\(i)Tg", value: targetRPM) && ok
            ok = write("F\(i)Md", value: 1) && ok
        }
        return ok
    }

    /// Return all fans to automatic (SMC-managed) control. Root only.
    func setFansAuto() -> Bool {
        var ok = fanCount > 0
        for i in 0..<fanCount {
            ok = write("F\(i)Md", value: 0) && ok
        }
        return ok
    }

    /// Total system power draw in watts, probing known keys.
    func systemPowerWatts() -> Double? {
        for key in ["PSTR", "PDTR", "PPT "] {
            if let value = read(key), value > 0, value < 1000 {
                return value
            }
        }
        return nil
    }
}
