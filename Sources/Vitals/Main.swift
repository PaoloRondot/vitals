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
        case "test":
            // Safe probe of what fan writes do on this SMC generation:
            // only ever raises the target, and restores state afterwards.
            let hasMode = smc.keyInfo("F0Md") != nil
            let originalTarget = smc.read("F0Tg") ?? 0
            print("mode key: \(hasMode ? "present" : "absent"), target before: \(Int(originalTarget))")
            let probe = max(originalTarget + 800, 5800)
            print("writing F0Tg=\(Int(probe)): \(smc.write("F0Tg", value: probe) ? "ok" : "REJECTED")")
            Thread.sleep(forTimeInterval: 6)
            let heldTarget = smc.read("F0Tg") ?? 0
            let actual = smc.read("F0Ac") ?? 0
            print("after 6s: target \(Int(heldTarget)), actual \(Int(actual)) (held: \(abs(heldTarget - probe) < 50))")
            print("writing F0Tg=0 (auto-restore probe): \(smc.write("F0Tg", value: 0) ? "ok" : "REJECTED")")
            Thread.sleep(forTimeInterval: 5)
            let restored = smc.read("F0Tg") ?? 0
            print("after 5s: target \(Int(restored)) (firmware retook control: \(restored > 100 && abs(restored - probe) > 100))")
            if restored < 100 {
                // Firmware didn't retake control; put the original target back.
                _ = smc.write("F0Tg", value: originalTarget)
                print("restored original target \(Int(originalTarget))")
            }
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
        for key in ["F0Md", "F0Tg", "F0Mn", "F0Mx", "FS! "] {
            if let info = smc.keyInfo(key) {
                print("key '\(key)': type '\(info.type)', size \(info.size), attributes 0x\(String(info.attributes, radix: 16))")
            } else {
                print("key '\(key)': absent")
            }
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
        let gpu = GPUReader()
        let disk = DiskReader()
        let battery = BatteryReader()
        let smc = SMCClient()

        // CPU load, network/disk rates, and clocks are deltas; prime and wait.
        _ = cpu.read()
        _ = network.read()
        _ = frequency.read()
        _ = gpu.read()
        _ = disk.readIO()
        Thread.sleep(forTimeInterval: 1.0)

        let load = cpu.read()
        let freq = frequency.read()
        let gpuStats = gpu.read()
        let diskIO = disk.readIO()
        let ram = memory.readRAM()
        let swap = memory.readSwap()
        let net = network.read()
        let temp = temperature.read()
        let fans = smc?.fanSpeeds() ?? []
        let watts = smc?.systemPowerWatts()

        print("CPU load:  \(Format.percent(load.total))  (per core: \(load.perCore.map { Format.percent($0) }.joined(separator: " ")))")
        print("CPU temp:  \(temp.map { String(format: "%.1f°C", $0) } ?? "unavailable")")
        print("CPU freq:  \(freq.map { String(format: "P %.2f GHz, E %.2f GHz", $0.pMHz / 1000, $0.eMHz / 1000) } ?? "unavailable")")
        print("GPU:       \(gpuStats.map { String(format: "%.2f GHz, %.0f%% busy", $0.mhz / 1000, $0.busy * 100) } ?? "unavailable")")
        print("Disk I/O:  R \(Format.rate(diskIO.read))  W \(Format.rate(diskIO.write))")
        print("Volumes:   \(disk.volumes().map { "\($0.name) \(Format.bytesLong($0.free)) free" }.joined(separator: ", "))")
        if let b = battery.read() {
            print("Battery:   \(b.percent)%, \(b.isCharging ? "charging" : "discharging"), \(String(format: "%+.1f W", b.watts)), health \(b.healthPercent.map { String(format: "%.0f%%", $0) } ?? "?"), \(b.cycleCount) cycles")
        } else {
            print("Battery:   none")
        }
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
