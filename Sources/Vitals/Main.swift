import Foundation

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--sample") {
            SampleMode.run()
        } else if args.contains("--fan-info") {
            FanCtl.printInfo()
        } else if let index = args.firstIndex(of: "--fanctl") {
            FanCtl.run(Array(args[(index + 1)...]))
        } else {
            VitalsApp.main()
        }
    }
}

/// Privileged fan-control mode. The app invokes its own binary with
/// `--fanctl` through an admin-authorized shell (SMC writes require root).
enum FanCtl {
    static func run(_ args: [String]) -> Never {
        guard let smc = SMCClient() else { fail("cannot open SMC") }
        guard geteuid() == 0 else { fail("--fanctl requires root") }
        guard smc.fanCount > 0 else { fail("no fans present") }

        switch args.first {
        case "auto":
            guard smc.setFansAuto() else { fail("SMC write failed") }
            print("fans: automatic")
        case "set":
            guard args.count >= 2, let rpm = Double(args[1]) else { fail("usage: --fanctl set <rpm>") }
            guard let limits = smc.fanLimits() else { fail("cannot read fan limits") }
            let clamped = max(limits.min, min(limits.max, rpm))
            guard smc.setFans(targetRPM: clamped) else { fail("SMC write failed") }
            print("fans: forced to \(Int(clamped)) RPM")
        default:
            fail("usage: --fanctl auto | --fanctl set <rpm>")
        }
        exit(0)
    }

    static func printInfo() -> Never {
        guard let smc = SMCClient() else { fail("cannot open SMC") }
        print("fans: \(smc.fanCount), forced: \(smc.fansForced())")
        if let limits = smc.fanLimits() {
            print("limits: \(Int(limits.min))-\(Int(limits.max)) RPM")
        } else {
            print("limits: unavailable")
        }
        for i in 0..<smc.fanCount {
            let actual = smc.read("F\(i)Ac").map { String(Int($0)) } ?? "?"
            let target = smc.read("F\(i)Tg").map { String(Int($0)) } ?? "?"
            print("fan \(i): actual \(actual) RPM, target \(target) RPM")
        }
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("vitals: \(message)\n".utf8))
        exit(1)
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
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let ms = await LatencyProbe.measure()
            print("Latency:   \(ms.map { String(format: "%.0f ms", $0) } ?? "unreachable")")
            semaphore.signal()
        }
        semaphore.wait()
        print("Pressure:  level \(memory.pressureLevel()) (1 normal, 2 warning, 4 critical)")
        print("Fans:      \(fans.isEmpty ? "none detected" : fans.map { String(format: "%.0f RPM", $0) }.joined(separator: ", "))")
        print("Power:     \(watts.map { String(format: "%.1f W", $0) } ?? "unavailable")")

        let processes = ProcessReader.read()
        print("Top CPU:   \(processes.byCPU.prefix(3).map { "\($0.name) \(String(format: "%.1f%%", $0.cpuPercent))" }.joined(separator: ", "))")
        print("Top RAM:   \(processes.byMemory.prefix(3).map { "\($0.name) \(Format.bytesLong($0.memBytes))" }.joined(separator: ", "))")
        print("Top SWAP:  \(processes.bySwap.prefix(3).map { "\($0.name) \(Format.bytesLong($0.compressedBytes))" }.joined(separator: ", "))")
        exit(0)
    }
}
