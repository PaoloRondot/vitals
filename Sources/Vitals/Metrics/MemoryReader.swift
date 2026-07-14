import Darwin
import Foundation

/// RAM usage via host_statistics64 and swap via sysctl vm.swapusage.
final class MemoryReader {
    let totalRAM: UInt64
    private let pageSize: UInt64

    init() {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &len, nil, 0)
        totalRAM = size

        var page: UInt64 = 0
        len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.pagesize", &page, &len, nil, 0)
        pageSize = page > 0 ? page : 16_384
    }

    func readRAM() -> (used: UInt64, total: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, totalRAM) }
        // Matches Activity Monitor's "Memory Used" closely:
        // anonymous (internal minus purgeable) + wired + compressed.
        let internalPages = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
        let used = (internalPages &+ UInt64(stats.wire_count) &+ UInt64(stats.compressor_page_count)) &* pageSize
        return (min(used, totalRAM), totalRAM)
    }

    func readSwap() -> (used: UInt64, total: UInt64) {
        var swap = xsw_usage()
        var len = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &len, nil, 0) == 0 else { return (0, 0) }
        return (swap.xsu_used, swap.xsu_total)
    }
}
