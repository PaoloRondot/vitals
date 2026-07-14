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

    /// Manufacturer fan RPM bounds (nil when fanless or unavailable).
    let fanLimits: (min: Double, max: Double)?

    // Per-process sampling only runs while the popover is open.
    var topByCPU: [TopProcess] = []
    var topByMemory: [TopProcess] = []
    var topBySwap: [TopProcess] = []
    @ObservationIgnored private var processMonitoringActive = false
    @ObservationIgnored private var processRefreshInFlight = false

    // Latency probe state (measured every ~10 s, not every tick).
    @ObservationIgnored private var lastLatencyMs: Double?
    @ObservationIgnored private var latencyFailed = false
    @ObservationIgnored private var tick = 0

    init() {
        fanLimits = smc?.fanLimits()
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

        s.memoryPressureLevel = memoryReader.pressureLevel()
        s.latencyMs = lastLatencyMs
        s.latencyFailed = latencyFailed

        let net = networkReader.read()
        s.netDown = net.down
        s.netUp = net.up

        if let smc {
            s.fanRPMs = smc.fanSpeeds()
            s.fanForced = smc.fansForced()
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

        // Probe connection latency every 5th tick (~10 s).
        if tick % 5 == 0 {
            Task { [weak self] in
                let ms = await LatencyProbe.measure()
                guard let self else { return }
                self.lastLatencyMs = ms
                self.latencyFailed = (ms == nil)
                self.snapshot.latencyMs = ms
                self.snapshot.latencyFailed = (ms == nil)
            }
        }
        tick += 1
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
            self.topBySwap = result.bySwap
        }
    }
}
