import AppKit
import SwiftUI

/// One stacked menu bar element: value on top, tiny caption below.
private struct MenuBarStack: View {
    var value: String
    var label: String

    var body: some View {
        VStack(spacing: -1) {
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 6.5, weight: .semibold))
                .kerning(0.5)
        }
    }
}

private struct MenuBarLabelView: View {
    var snapshot: Snapshot

    var body: some View {
        HStack(spacing: 8) {
            if let temp = snapshot.cpuTemp {
                MenuBarStack(value: Format.temperature(temp), label: "CPU")
            }
            if let ghz = snapshot.cpuGHz {
                MenuBarStack(value: String(format: "%.1f", ghz), label: "GHZ")
            }
            MenuBarStack(value: Format.percent(snapshot.cpuLoad), label: "LOAD")
            MenuBarStack(value: Format.bytes(snapshot.ramUsed), label: "RAM")
        }
        .foregroundStyle(.black)
        .fixedSize()
    }
}

/// MenuBarExtra can't render stacked multi-line labels directly, so the
/// two-line layout is rasterized into a template image the menu bar tints
/// to match light/dark appearance.
@MainActor
enum MenuBarImage {
    static func render(_ snapshot: Snapshot) -> NSImage {
        let renderer = ImageRenderer(content: MenuBarLabelView(snapshot: snapshot))
        renderer.scale = 2
        guard let image = renderer.nsImage else { return NSImage() }
        image.isTemplate = true
        return image
    }
}
