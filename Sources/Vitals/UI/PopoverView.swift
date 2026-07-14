import ServiceManagement
import SwiftUI

enum StatTab: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "MEM"
    case network = "NET"
    case disk = "DISK"
    case battery = "BATT"
    var id: String { rawValue }
}

struct PopoverView: View {
    var sampler: Sampler
    @AppStorage("selectedTab") private var tabRaw = StatTab.cpu.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var tab: Binding<StatTab> {
        Binding(get: { StatTab(rawValue: tabRaw) ?? .cpu },
                set: { tabRaw = $0.rawValue })
    }

    private var isBundled: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: tab) {
                ForEach(StatTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab.wrappedValue {
            case .cpu: CPUTab(sampler: sampler)
            case .memory: MemoryTab(sampler: sampler)
            case .network: NetworkTab(sampler: sampler)
            case .disk: DiskTab(sampler: sampler)
            case .battery: BatteryTab(sampler: sampler)
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
        .frame(width: 320)
        .onAppear { sampler.setProcessMonitoring(true) }
        .onDisappear { sampler.setProcessMonitoring(false) }
    }
}
