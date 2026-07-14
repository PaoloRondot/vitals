import SwiftUI

enum Severity: Equatable {
    case normal, warning, critical

    /// nil means "use the default color".
    var color: Color? {
        switch self {
        case .normal: nil
        case .warning: .orange
        case .critical: .red
        }
    }
}

extension Snapshot {
    var cpuSeverity: Severity {
        cpuLoad >= 0.95 ? .critical : cpuLoad >= 0.80 ? .warning : .normal
    }

    var tempSeverity: Severity {
        guard let temp = cpuTemp else { return .normal }
        return temp >= 90 ? .critical : temp >= 75 ? .warning : .normal
    }

    var ramSeverity: Severity {
        // Kernel pressure levels: 1 normal, 2 warning, 4 critical.
        switch memoryPressureLevel {
        case 4: .critical
        case 2: .warning
        default: ramFraction > 0.92 ? .warning : .normal
        }
    }

    var networkSeverity: Severity {
        if latencyFailed { return .critical }
        guard let ms = latencyMs else { return .normal }
        return ms >= 400 ? .critical : ms >= 150 ? .warning : .normal
    }
}
