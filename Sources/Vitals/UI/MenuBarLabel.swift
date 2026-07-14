import AppKit
import SwiftUI

/// One stacked menu bar element: value on top, tiny caption below.
private struct MenuBarStack: View {
    var value: String
    var label: String
    var base: Color
    var accent: Color?

    var body: some View {
        VStack(spacing: -1) {
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(accent ?? base)
            Text(label)
                .font(.system(size: 6.5, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(base)
        }
    }
}

private struct MenuBarLabelView: View {
    var snapshot: Snapshot
    var base: Color

    var body: some View {
        HStack(spacing: 8) {
            if let temp = snapshot.cpuTemp {
                MenuBarStack(value: Format.temperature(temp), label: "CPU",
                             base: base, accent: snapshot.tempSeverity.color)
            }
            if let ghz = snapshot.cpuGHz {
                MenuBarStack(value: String(format: "%.1f", ghz), label: "GHZ",
                             base: base, accent: nil)
            }
            MenuBarStack(value: Format.percent(snapshot.cpuLoad), label: "LOAD",
                         base: base, accent: snapshot.cpuSeverity.color)
            MenuBarStack(value: Format.bytes(snapshot.ramUsed), label: "RAM",
                         base: base, accent: snapshot.ramSeverity.color)
        }
        .fixedSize()
    }
}

/// MenuBarExtra can't render stacked multi-line labels directly, so the
/// two-line layout is rasterized into an image. When every metric is normal
/// the image is a template that the menu bar tints for light/dark; when any
/// metric runs hot, it renders in color (template and color are exclusive),
/// with the base color matched to the current appearance.
@MainActor
enum MenuBarImage {
    static func render(_ snapshot: Snapshot) -> NSImage {
        let anyHot = [snapshot.tempSeverity, snapshot.cpuSeverity, snapshot.ramSeverity]
            .contains { $0 != .normal }
        // NSApplication.shared, not NSApp: the first sample runs during App
        // init, before NSApp is populated.
        let appearance = NSApplication.shared.effectiveAppearance
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base: Color = anyHot ? (dark ? .white : .black) : .black

        let renderer = ImageRenderer(content: MenuBarLabelView(snapshot: snapshot, base: base))
        renderer.scale = 2
        guard let image = renderer.nsImage else { return NSImage() }
        image.isTemplate = !anyHot
        return image
    }
}
