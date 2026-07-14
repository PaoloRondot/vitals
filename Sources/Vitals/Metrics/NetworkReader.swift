import Darwin
import Foundation

/// Network throughput from getifaddrs byte-counter deltas across en* interfaces.
final class NetworkReader {
    private var previous: (rx: UInt64, tx: UInt64, time: TimeInterval)?

    func read() -> (down: Double, up: Double) {
        var ifaddrList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrList) == 0 else { return (0, 0) }
        defer { freeifaddrs(ifaddrList) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var cursor = ifaddrList
        while let current = cursor {
            let ifa = current.pointee
            cursor = ifa.ifa_next
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let dataPtr = ifa.ifa_data else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
            rx &+= UInt64(data.ifi_ibytes)
            tx &+= UInt64(data.ifi_obytes)
        }

        let now = Date().timeIntervalSinceReferenceDate
        defer { previous = (rx, tx, now) }
        guard let prev = previous, now > prev.time else { return (0, 0) }

        let elapsed = now - prev.time
        // Counters are 32-bit and can wrap or reset; clamp to zero on decrease.
        let down = rx >= prev.rx ? Double(rx - prev.rx) / elapsed : 0
        let up = tx >= prev.tx ? Double(tx - prev.tx) / elapsed : 0
        return (down, up)
    }
}
