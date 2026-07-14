import Foundation

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--sample") {
            SampleMode.run()
        } else {
            VitalsApp.main()
        }
    }
}

/// Headless one-shot mode: print every metric to stdout and exit.
/// Useful for verifying the sensor plumbing without the GUI:
///   VITALS_DEBUG=1 swift run Vitals --sample
enum SampleMode {
    static func run() -> Never {
        let cpu = CPULoadReader()
        let memory = MemoryReader()
        let network = NetworkReader()
        let temperature = TemperatureReader()
        let frequency = FrequencyReader()
        let smc = SMCClient()

        // CPU load, network rates, and clocks are deltas; prime and wait a beat.
        _ = cpu.read()
        _ = network.read()
        _ = frequency.read()
        Thread.sleep(forTimeInterval: 1.0)

        let load = cpu.read()
        let freq = frequency.read()
        let ram = memory.readRAM()
        let swap = memory.readSwap()
        let net = network.read()
        let temp = temperature.read()
        let fans = smc?.fanSpeeds() ?? []
        let watts = smc?.systemPowerWatts()

        print("CPU load:  \(Format.percent(load.total))  (per core: \(load.perCore.map { Format.percent($0) }.joined(separator: " ")))")
        print("CPU temp:  \(temp.map { String(format: "%.1f°C", $0) } ?? "unavailable")")
        print("CPU freq:  \(freq.map { String(format: "P %.2f GHz, E %.2f GHz", $0.pMHz / 1000, $0.eMHz / 1000) } ?? "unavailable")")
        print("RAM:       \(Format.bytesLong(ram.used)) / \(Format.bytesLong(ram.total))")
        print("Swap:      \(Format.bytesLong(swap.used)) / \(Format.bytesLong(swap.total))")
        print("Network:   ↓ \(Format.rate(net.down))  ↑ \(Format.rate(net.up))")
        print("Fans:      \(fans.isEmpty ? "none detected" : fans.map { String(format: "%.0f RPM", $0) }.joined(separator: ", "))")
        print("Power:     \(watts.map { String(format: "%.1f W", $0) } ?? "unavailable")")

        let processes = ProcessReader.read()
        print("Top CPU:   \(processes.byCPU.prefix(3).map { "\($0.name) \(String(format: "%.1f%%", $0.cpuPercent))" }.joined(separator: ", "))")
        print("Top RAM:   \(processes.byMemory.prefix(3).map { "\($0.name) \(Format.bytesLong($0.memBytes))" }.joined(separator: ", "))")
        print("Top SWAP:  \(processes.bySwap.prefix(3).map { "\($0.name) \(Format.bytesLong($0.compressedBytes))" }.joined(separator: ", "))")
        exit(0)
    }
}
