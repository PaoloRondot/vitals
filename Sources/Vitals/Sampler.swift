import AppKit
import Foundation
import Observation

/// Owns the metric readers, samples every 2 s, and publishes the latest
/// snapshot plus sparkline histories to the UI.
@MainActor @Observable
final class Sampler {
    var snapshot = Snapshot()
    var menuBarImage = NSImage()
    var cpuHistory = History()
    var tempHistory = History()
    var ramHistory = History()
    var downHistory = History()
    var upHistory = History()

    @ObservationIgnored private let cpuReader = CPULoadReader()
    @ObservationIgnored private let memoryReader = MemoryReader()
    @ObservationIgnored private let networkReader = NetworkReader()
    @ObservationIgnored private let temperatureReader = TemperatureReader()
    @ObservationIgnored private let frequencyReader = FrequencyReader()
    @ObservationIgnored private let smc = SMCClient()
    @ObservationIgnored private var task: Task<Void, Never>?

    // Per-process sampling only runs while the popover is open.
    var topByCPU: [TopProcess] = []
    var topByMemory: [TopProcess] = []
    @ObservationIgnored private var processMonitoringActive = false
    @ObservationIgnored private var processRefreshInFlight = false

    init() {
        sample()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.sample()
            }
        }
    }

    func sample() {
        var s = Snapshot()

        let cpu = cpuReader.read()
        s.cpuLoad = cpu.total
        s.perCoreLoad = cpu.perCore

        s.cpuTemp = temperatureReader.read()

        if let freq = frequencyReader.read() {
            s.eCoreMHz = freq.eMHz
            s.pCoreMHz = freq.pMHz
        }

        let ram = memoryReader.readRAM()
        s.ramUsed = ram.used
        s.ramTotal = ram.total

        let swap = memoryReader.readSwap()
        s.swapUsed = swap.used
        s.swapTotal = swap.total

        let net = networkReader.read()
        s.netDown = net.down
        s.netUp = net.up

        if let smc {
            s.fanRPMs = smc.fanSpeeds()
            s.powerWatts = smc.systemPowerWatts()
        }

        snapshot = s
        menuBarImage = MenuBarImage.render(s)
        cpuHistory.append(s.cpuLoad)
        if let temp = s.cpuTemp { tempHistory.append(temp) }
        ramHistory.append(s.ramFraction)
        downHistory.append(s.netDown)
        upHistory.append(s.netUp)

        if processMonitoringActive {
            refreshProcesses()
        }
    }

    func setProcessMonitoring(_ active: Bool) {
        processMonitoringActive = active
        if active {
            refreshProcesses()
        }
    }

    private func refreshProcesses() {
        guard !processRefreshInFlight else { return }
        processRefreshInFlight = true
        Task { [weak self] in
            // Only the blocking ps call leaves the main actor.
            let result = await Task.detached(priority: .utility) { ProcessReader.read() }.value
            guard let self else { return }
            self.processRefreshInFlight = false
            self.topByCPU = result.byCPU
            self.topByMemory = result.byMemory
        }
    }
}
