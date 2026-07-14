import AppKit
import SwiftUI

struct VitalsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var sampler = Sampler()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(sampler: sampler)
        } label: {
            Image(nsImage: sampler.menuBarImage)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only: no Dock icon even when run as a bare executable
        // (the bundled app also sets LSUIElement in Info.plist).
        NSApp.setActivationPolicy(.accessory)
    }
}
