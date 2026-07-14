import Foundation
import Network

/// Connection quality probe: time to open a TCP connection to a fast anycast
/// host. Throughput can't distinguish "idle" from "slow" — connect latency can.
enum LatencyProbe {
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        var connection: NWConnection?

        /// Returns true the first time only.
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if finished { return false }
            finished = true
            return true
        }
    }

    /// Round-trip estimate in milliseconds, or nil on timeout/no connectivity.
    static func measure(host: String = "1.1.1.1", port: UInt16 = 443,
                        timeout: TimeInterval = 2.0) async -> Double? {
        let state = State()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let connection = NWConnection(host: NWEndpoint.Host(host),
                                          port: NWEndpoint.Port(rawValue: port)!,
                                          using: .tcp)
            state.connection = connection
            let start = DispatchTime.now()

            let finish: @Sendable (Double?) -> Void = { value in
                guard state.claim() else { return }
                state.connection?.cancel()
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                    finish(Double(elapsed) / 1_000_000)
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                finish(nil)
            }
        }
    }
}
