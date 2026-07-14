import ServiceManagement
import SwiftUI

enum ProcessSort {
    case cpu, memory, swap
}

struct PopoverView: View {
    var sampler: Sampler
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var processSort: ProcessSort = .cpu

    private var isBundled: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    var body: some View {
        let s = sampler.snapshot
        VStack(alignment: .leading, spacing: 12) {
            // CPU
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("CPU", systemImage: "cpu")
                        .font(.headline)
                    Spacer()
                    if let temp = s.cpuTemp {
                        Text(String(format: "%.1f°C", temp))
                            .foregroundStyle(temp > 85 ? .red : .secondary)
                    }
                    Text(Format.percent(s.cpuLoad))
                        .font(.headline.monospacedDigit())
                }
                Sparkline(values: sampler.cpuHistory.values, maxValue: 1, color: .blue)
                    .frame(height: 28)
                if s.eCoreMHz != nil || s.pCoreMHz != nil {
                    HStack {
                        if let p = s.pCoreMHz, p > 0 {
                            Text(String(format: "P-cores %.2f GHz", p / 1000))
                        }
                        if let e = s.eCoreMHz, e > 0 {
                            Text(String(format: "E-cores %.2f GHz", e / 1000))
                        }
                        Spacer()
                    }
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            // Memory
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Memory", systemImage: "memorychip")
                        .font(.headline)
                    Spacer()
                    Text("\(Format.bytesLong(s.ramUsed)) / \(Format.bytesLong(s.ramTotal))")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: s.ramFraction)
                    .tint(s.ramFraction > 0.85 ? .orange : .green)
                HStack {
                    Text("Swap")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(s.swapTotal > 0
                         ? "\(Format.bytesLong(s.swapUsed)) / \(Format.bytesLong(s.swapTotal))"
                         : Format.bytesLong(s.swapUsed))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            // Network
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Network", systemImage: "network")
                        .font(.headline)
                    Spacer()
                    Text("↓ \(Format.rate(s.netDown))   ↑ \(Format.rate(s.netUp))")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Sparkline(values: sampler.downHistory.values, color: .purple)
                    .frame(height: 22)
            }

            // Fans & power (hidden when unavailable)
            if !s.fanRPMs.isEmpty || s.powerWatts != nil {
                HStack {
                    if !s.fanRPMs.isEmpty {
                        Label(s.fanRPMs.map { String(format: "%.0f RPM", $0) }.joined(separator: "  "),
                              systemImage: "fan")
                    }
                    Spacer()
                    if let watts = s.powerWatts {
                        Label(String(format: "%.1f W", watts), systemImage: "bolt")
                    }
                }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Divider()

            // Top processes
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Top Processes", systemImage: "list.number")
                        .font(.headline)
                    Spacer()
                    Picker("", selection: $processSort) {
                        Text("CPU").tag(ProcessSort.cpu)
                        Text("RAM").tag(ProcessSort.memory)
                        Text("SWAP").tag(ProcessSort.swap)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }
                let processes = switch processSort {
                case .cpu: sampler.topByCPU
                case .memory: sampler.topByMemory
                case .swap: sampler.topBySwap
                }
                if processes.isEmpty {
                    Text("Sampling…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(processes) { process in
                        let value = switch processSort {
                        case .cpu: String(format: "%.1f%%", process.cpuPercent)
                        case .memory: Format.bytesLong(process.memBytes)
                        case .swap: Format.bytesLong(process.compressedBytes)
                        }
                        HStack {
                            Text(process.name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text(value)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }

            Divider()

            HStack {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .disabled(!isBundled)
                    .help(isBundled ? "Start Vitals automatically when you log in"
                                    : "Available when running the bundled Vitals.app")
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { sampler.setProcessMonitoring(true) }
        .onDisappear { sampler.setProcessMonitoring(false) }
    }
}
