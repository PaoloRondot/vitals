import SwiftUI

// MARK: - Shared pieces

private struct ProcessList: View {
    var processes: [TopProcess]
    var value: (TopProcess) -> String

    var body: some View {
        if processes.isEmpty {
            Text("Sampling…")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(processes) { process in
                HStack {
                    Text(process.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(value(process))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
    }
}

private struct DetailRow: View {
    var label: String
    var value: String
    var valueColor: Color? = nil

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(valueColor ?? .primary)
        }
        .font(.callout)
    }
}

// MARK: - CPU

struct CPUTab: View {
    var sampler: Sampler
    @State private var fanManual = false
    @State private var fanTarget: Double = 0
    @State private var fanBusy = false
    @State private var fanError: String?
    @State private var suppressFanChange = false

    var body: some View {
        let s = sampler.snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("CPU", systemImage: "cpu")
                    .font(.headline)
                Spacer()
                if let temp = s.cpuTemp {
                    Text(String(format: "%.1f°C", temp))
                        .foregroundStyle(s.tempSeverity.color ?? .secondary)
                }
                Text(Format.percent(s.cpuLoad))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(s.cpuSeverity.color ?? .primary)
            }
            Sparkline(values: sampler.cpuHistory.values, maxValue: 1, color: .blue)
                .frame(height: 28)

            if s.pCoreMHz != nil || s.eCoreMHz != nil {
                DetailRow(label: "Clocks",
                          value: [s.pCoreMHz.map { String(format: "P %.2f GHz", $0 / 1000) },
                                  s.eCoreMHz.map { String(format: "E %.2f GHz", $0 / 1000) }]
                            .compactMap(\.self).joined(separator: "   "))
            }
            if let mhz = s.gpuMHz, let busy = s.gpuBusy {
                DetailRow(label: "GPU",
                          value: String(format: "%.2f GHz   %@", mhz / 1000, Format.percent(busy)))
            }
            if !s.fanRPMs.isEmpty || s.powerWatts != nil {
                DetailRow(label: s.fanRPMs.isEmpty ? "Power" : "Fan",
                          value: [s.fanRPMs.isEmpty ? nil
                                    : s.fanRPMs.map { String(format: "%.0f RPM", $0) }.joined(separator: "  "),
                                  s.powerWatts.map { String(format: "%.1f W", $0) }]
                            .compactMap(\.self).joined(separator: "   "))
            }

            if sampler.fanControlSupported, let limits = sampler.fanLimits {
                HStack(spacing: 8) {
                    Picker("", selection: $fanManual) {
                        Text("Auto").tag(false)
                        Text("Manual").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(fanBusy)
                    .onChange(of: fanManual) { wasManual, isManual in
                        guard !suppressFanChange, wasManual != isManual else { return }
                        if !isManual { applyFan("auto") }
                    }
                    if fanManual {
                        Slider(value: $fanTarget, in: limits.min...limits.max)
                        Text("\(Int(fanTarget))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                        Button("Set") { applyFan("set \(Int(fanTarget))") }
                            .disabled(fanBusy)
                    }
                }
                if let error = fanError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Divider()
            ProcessList(processes: sampler.topByCPU) {
                String(format: "%.1f%%", $0.cpuPercent)
            }
        }
        .onAppear {
            suppressFanChange = true
            fanManual = sampler.snapshot.fanForced
            suppressFanChange = false
            if fanTarget == 0 {
                fanTarget = sampler.snapshot.fanRPMs.first ?? sampler.fanLimits?.min ?? 0
            }
        }
    }

    private func applyFan(_ command: String) {
        fanBusy = true
        fanError = nil
        Task {
            let error = await FanControl.apply(command)
            fanBusy = false
            if let error {
                if error != "cancelled" { fanError = error }
                suppressFanChange = true
                fanManual = sampler.snapshot.fanForced
                suppressFanChange = false
            }
        }
    }
}

// MARK: - Memory

private enum MemorySort: String {
    case ram = "RAM", swap = "SWAP"
}

struct MemoryTab: View {
    var sampler: Sampler
    @State private var sort: MemorySort = .ram

    var body: some View {
        let s = sampler.snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Memory", systemImage: "memorychip")
                    .font(.headline)
                Spacer()
                Text("\(Format.bytesLong(s.ramUsed)) / \(Format.bytesLong(s.ramTotal))")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: s.ramFraction)
                .tint(s.ramSeverity.color ?? .green)

            DetailRow(label: "Swap",
                      value: s.swapTotal > 0
                        ? "\(Format.bytesLong(s.swapUsed)) / \(Format.bytesLong(s.swapTotal))"
                        : Format.bytesLong(s.swapUsed))
            DetailRow(label: "Pressure",
                      value: s.memoryPressureLevel == 4 ? "critical"
                           : s.memoryPressureLevel == 2 ? "warning" : "normal",
                      valueColor: s.ramSeverity.color)

            Divider()
            HStack {
                Text("Top Processes")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("", selection: $sort) {
                    Text(MemorySort.ram.rawValue).tag(MemorySort.ram)
                    Text(MemorySort.swap.rawValue).tag(MemorySort.swap)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if sort == .ram {
                ProcessList(processes: sampler.topByMemory) { Format.bytesLong($0.memBytes) }
            } else {
                ProcessList(processes: sampler.topBySwap) { Format.bytesLong($0.compressedBytes) }
            }
        }
    }
}

// MARK: - Network

struct NetworkTab: View {
    var sampler: Sampler

    var body: some View {
        let s = sampler.snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Network", systemImage: "network")
                    .font(.headline)
                if s.latencyFailed {
                    Text("● offline")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let ms = s.latencyMs {
                    Text(String(format: "● %.0f ms", ms))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(s.networkSeverity.color ?? .green)
                        .help("TCP connect time to 1.1.1.1")
                }
                Spacer()
            }
            DetailRow(label: "Download", value: Format.rate(s.netDown))
            Sparkline(values: sampler.downHistory.values, color: .purple)
                .frame(height: 24)
            DetailRow(label: "Upload", value: Format.rate(s.netUp))
            Sparkline(values: sampler.upHistory.values, color: .teal)
                .frame(height: 24)
        }
    }
}

// MARK: - Disk

struct DiskTab: View {
    var sampler: Sampler

    var body: some View {
        let s = sampler.snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Disk", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                Text("R \(Format.rate(s.diskRead))   W \(Format.rate(s.diskWrite))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if s.volumes.isEmpty {
                Text("No volumes")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(s.volumes) { volume in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(volume.name)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Format.bytesLong(volume.free)) free of \(Format.bytesLong(volume.total))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: volume.usedFraction)
                        .tint(volume.usedFraction > 0.9 ? .red
                              : volume.usedFraction > 0.75 ? .orange : .green)
                }
            }
        }
    }
}

// MARK: - Battery

struct BatteryTab: View {
    var sampler: Sampler

    var body: some View {
        let s = sampler.snapshot
        VStack(alignment: .leading, spacing: 10) {
            if let battery = s.battery {
                HStack {
                    Label("Battery", systemImage: battery.isCharging ? "battery.100.bolt" : "battery.75")
                        .font(.headline)
                    Spacer()
                    Text("\(battery.percent)%")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(battery.percent <= 10 ? .red : .primary)
                }
                ProgressView(value: Double(battery.percent) / 100)
                    .tint(battery.percent <= 10 ? .red : battery.percent <= 25 ? .orange : .green)

                DetailRow(label: "State",
                          value: battery.isCharging ? "charging"
                               : battery.fullyCharged ? "full"
                               : battery.externalConnected ? "on AC" : "discharging")
                DetailRow(label: "Power",
                          value: String(format: "%+.1f W", battery.watts))
                if let minutes = battery.timeRemainingMinutes {
                    DetailRow(label: battery.isCharging ? "Until full" : "Remaining",
                              value: String(format: "%d:%02d", minutes / 60, minutes % 60))
                }
                if let health = battery.healthPercent {
                    DetailRow(label: "Health",
                              value: String(format: "%.0f%%", health),
                              valueColor: health < 80 ? .orange : nil)
                }
                DetailRow(label: "Cycles", value: "\(battery.cycleCount)")
                if let temp = battery.temperature {
                    DetailRow(label: "Temperature", value: String(format: "%.1f°C", temp))
                }
            } else {
                Label("No battery", systemImage: "battery.slash")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
