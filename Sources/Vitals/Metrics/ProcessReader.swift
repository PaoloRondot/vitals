import Foundation

struct TopProcess: Identifiable, Sendable {
    let pid: Int
    let name: String
    let cpuPercent: Double
    let memBytes: UInt64
    var id: Int { pid }
}

/// Per-process CPU/RAM via /bin/ps (only sampled while the popover is open).
enum ProcessReader {
    static func read() -> (byCPU: [TopProcess], byMemory: [TopProcess]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Aceo", "pid=,pcpu=,rss=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        guard (try? task.run()) != nil,
              let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8) else {
            return ([], [])
        }
        task.waitUntilExit()

        var processes: [TopProcess] = []
        for line in output.split(separator: "\n") {
            // pid, pcpu, rss(KB), then the command name (which may contain spaces).
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  let pid = Int(fields[0]),
                  let cpu = Double(fields[1]),
                  let rssKB = UInt64(fields[2]) else { continue }
            processes.append(TopProcess(pid: pid,
                                        name: String(fields[3]),
                                        cpuPercent: cpu,
                                        memBytes: rssKB * 1024))
        }

        let byCPU = Array(processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(7))
        let byMemory = Array(processes.sorted { $0.memBytes > $1.memBytes }.prefix(7))
        return (byCPU, byMemory)
    }
}
