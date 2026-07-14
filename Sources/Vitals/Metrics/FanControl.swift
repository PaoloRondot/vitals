import AppKit
import Foundation

/// Runs the app's own binary in `--fanctl` mode through an
/// admin-authorized shell (macOS password prompt) since SMC writes need root.
enum FanControl {
    /// Returns nil on success, "cancelled" if the user dismissed the auth
    /// dialog, or an error description.
    static func apply(_ command: String) async -> String? {
        let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let script = "do shell script \"'\(executable)' --fanctl \(command)\" with administrator privileges"
        return await Task.detached(priority: .userInitiated) { () -> String? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let stderrPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return "couldn't run osascript"
            }
            let errorData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            process.waitUntilExit()
            if process.terminationStatus == 0 { return nil }
            let message = String(data: errorData, encoding: .utf8) ?? ""
            return message.contains("-128") ? "cancelled" : "fan control failed"
        }.value
    }
}
