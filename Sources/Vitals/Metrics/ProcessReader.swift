import Foundation

struct TopProcess: Identifiable, Sendable {
    let pid: Int
    let name: String
    let cpuPercent: Double
    let memBytes: UInt64
    var compressedBytes: UInt64 = 0
    var id: Int { pid }
}

/// Per-process CPU/RAM/compressed via /bin/ps and /usr/bin/top
/// (only sampled while the popover is open).
enum ProcessReader {
    static func read() -> (byCPU: [TopProcess], byMemory: [TopProcess], bySwap: [TopProcess]) {
        guard let psOutput = run("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,comm="]) else {
            return ([], [], [])
        }

        var processes: [TopProcess] = []
        var byPid: [Int: Int] = [:] // pid -> index into processes
        for line in psOutput.split(separator: "\n") {
            // pid, pcpu, rss(KB), then the command name (which may contain spaces).
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  let pid = Int(fields[0]),
                  let cpu = Double(fields[1]),
                  let rssKB = UInt64(fields[2]) else { continue }
            byPid[pid] = processes.count
            processes.append(TopProcess(pid: pid,
                                        name: String(fields[3]),
                                        cpuPercent: cpu,
                                        memBytes: rssKB * 1024))
        }

        // macOS has no true per-process swap counter; compressed memory
        // (compressor pool + paged to disk) is the closest — it's what grows
        // when a process gets squeezed out of RAM. Only `top` reports it;
        // names come from the ps pass to avoid top's truncated commands.
        if let topOutput = run("/usr/bin/top", ["-l", "1", "-o", "cmprs", "-n", "12", "-stats", "pid,cmprs"]) {
            var pastHeader = false
            for line in topOutput.split(separator: "\n") {
                let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                if !pastHeader {
                    pastHeader = fields.first == "PID"
                    continue
                }
                guard fields.count >= 2, let pid = Int(fields[0]),
                      let bytes = parseTopSize(String(fields[1])),
                      let index = byPid[pid] else { continue }
                processes[index].compressedBytes = bytes
            }
        }

        let byCPU = Array(processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(7))
        let byMemory = Array(processes.sorted { $0.memBytes > $1.memBytes }.prefix(7))
        let bySwap = Array(processes.sorted { $0.compressedBytes > $1.compressedBytes }
            .prefix(7).filter { $0.compressedBytes > 0 })
        return (byCPU, byMemory, bySwap)
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil,
              let data = try? pipe.fileHandleForReading.readToEnd() else { return nil }
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// top prints sizes like "25G", "612M", "1024K", "0B".
    private static func parseTopSize(_ value: String) -> UInt64? {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        guard let unit = trimmed.last else { return nil }
        let number = String(trimmed.dropLast())
        guard let base = Double(number) else { return nil }
        switch unit {
        case "B": return UInt64(base)
        case "K": return UInt64(base * 1_024)
        case "M": return UInt64(base * 1_048_576)
        case "G": return UInt64(base * 1_073_741_824)
        default: return Double(trimmed).map { UInt64($0) }
        }
    }
}
