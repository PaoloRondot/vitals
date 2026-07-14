import Darwin
import Foundation

/// Aggregate and per-core CPU load from tick deltas between samples.
final class CPULoadReader {
    private var previousTicks: [[UInt64]] = []

    func read() -> (total: Double, perCore: [Double]) {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return (0, []) }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let stateCount = Int(CPU_STATE_MAX)
        var ticks: [[UInt64]] = []
        ticks.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            var states = [UInt64](repeating: 0, count: stateCount)
            for state in 0..<stateCount {
                states[state] = UInt64(UInt32(bitPattern: info[core * stateCount + state]))
            }
            ticks.append(states)
        }

        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count else { return (0, []) }

        var perCore: [Double] = []
        var busyTotal: UInt64 = 0
        var allTotal: UInt64 = 0
        for core in 0..<ticks.count {
            // Counters are 32-bit in the kernel; use wrapping deltas.
            let user = ticks[core][Int(CPU_STATE_USER)] &- previousTicks[core][Int(CPU_STATE_USER)]
            let system = ticks[core][Int(CPU_STATE_SYSTEM)] &- previousTicks[core][Int(CPU_STATE_SYSTEM)]
            let nice = ticks[core][Int(CPU_STATE_NICE)] &- previousTicks[core][Int(CPU_STATE_NICE)]
            let idle = ticks[core][Int(CPU_STATE_IDLE)] &- previousTicks[core][Int(CPU_STATE_IDLE)]
            let busy = user &+ system &+ nice
            let total = busy &+ idle
            perCore.append(total > 0 ? Double(busy) / Double(total) : 0)
            busyTotal &+= busy
            allTotal &+= total
        }
        let aggregate = allTotal > 0 ? Double(busyTotal) / Double(allTotal) : 0
        return (aggregate, perCore)
    }
}
