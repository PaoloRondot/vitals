import Foundation
import IOKit

struct VolumeInfo: Identifiable {
    let id: String   // mount path
    let name: String
    let free: UInt64
    let total: UInt64

    var usedFraction: Double {
        total > 0 ? Double(total - min(free, total)) / Double(total) : 0
    }
}

/// Disk throughput from IOBlockStorageDriver statistics deltas, plus
/// per-volume capacity via FileManager.
final class DiskReader {
    private var previous: (read: UInt64, write: UInt64, time: TimeInterval)?

    func readIO() -> (read: Double, write: Double) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let statsRef = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString,
                                                              kCFAllocatorDefault, 0),
               let stats = statsRef.takeRetainedValue() as? [String: Any] {
                read &+= stats["Bytes (Read)"] as? UInt64 ?? 0
                write &+= stats["Bytes (Write)"] as? UInt64 ?? 0
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }

        let now = Date().timeIntervalSinceReferenceDate
        defer { previous = (read, write, now) }
        guard let prev = previous, now > prev.time,
              read >= prev.read, write >= prev.write else { return (0, 0) }
        let elapsed = now - prev.time
        return (Double(read - prev.read) / elapsed, Double(write - prev.write) / elapsed)
    }

    func volumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                               options: [.skipHiddenVolumes]) else {
            return []
        }
        var seenNames = Set<String>()
        var result: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let total = values.volumeTotalCapacity, total > 0 else { continue }
            let name = values.volumeName ?? url.lastPathComponent
            guard seenNames.insert(name).inserted else { continue } // system/data dupes
            let free = values.volumeAvailableCapacityForImportantUsage ?? 0
            result.append(VolumeInfo(id: url.path, name: name,
                                     free: UInt64(max(free, 0)), total: UInt64(total)))
        }
        return result
    }
}
