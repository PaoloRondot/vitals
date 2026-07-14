import Foundation
import UserNotifications

/// Posts a notification when a metric transitions into critical, with a
/// 10-minute per-metric cooldown. Notifications need a real bundle, so this
/// is inert under `swift run`.
@MainActor
final class Notifier {
    private let enabled: Bool
    private var critical: Set<String> = []
    private var lastFired: [String: Date] = [:]

    init() {
        enabled = Bundle.main.bundlePath.hasSuffix(".app")
        guard enabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate(_ s: Snapshot) {
        guard enabled else { return }
        check("temp", s.tempSeverity == .critical,
              title: "CPU running hot",
              body: s.cpuTemp.map { String(format: "CPU temperature is %.0f °C.", $0) } ?? "")
        check("pressure", s.memoryPressureLevel == 4,
              title: "Memory pressure critical",
              body: "macOS is critically low on memory — consider closing apps.")
        check("offline", s.latencyFailed,
              title: "Network unreachable",
              body: "Connectivity checks are failing.")
    }

    private func check(_ key: String, _ isCritical: Bool, title: String, body: String) {
        guard isCritical else {
            critical.remove(key)
            return
        }
        guard !critical.contains(key) else { return }
        critical.insert(key)

        let now = Date()
        guard now.timeIntervalSince(lastFired[key] ?? .distantPast) > 600 else { return }
        lastFired[key] = now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: "vitals.\(key).\(now.timeIntervalSince1970)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
