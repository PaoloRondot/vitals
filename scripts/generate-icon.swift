// Draws the Vitals app icon: a minimal white pulse line on a dark squircle.
// Usage: swift scripts/generate-icon.swift <output-1024.png>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Apple's icon grid: 824x824 content area centered in 1024, ~185pt corner radius.
let inset: CGFloat = 100
let squircle = NSBezierPath(roundedRect: NSRect(x: inset, y: inset,
                                                width: CGFloat(size) - 2 * inset,
                                                height: CGFloat(size) - 2 * inset),
                            xRadius: 185, yRadius: 185)
squircle.addClip()

NSGradient(colors: [
    NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.20, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1),
])!.draw(in: squircle, angle: -90)

// Faint baseline through the middle.
let baseline = NSBezierPath()
baseline.move(to: NSPoint(x: 170, y: 512))
baseline.line(to: NSPoint(x: 854, y: 512))
baseline.lineWidth = 8
NSColor.white.withAlphaComponent(0.14).setStroke()
baseline.stroke()

// The pulse.
let pulse = NSBezierPath()
pulse.lineWidth = 36
pulse.lineCapStyle = .round
pulse.lineJoinStyle = .round
pulse.move(to: NSPoint(x: 170, y: 512))
pulse.line(to: NSPoint(x: 380, y: 512))
pulse.line(to: NSPoint(x: 445, y: 400))
pulse.line(to: NSPoint(x: 545, y: 690))
pulse.line(to: NSPoint(x: 625, y: 452))
pulse.line(to: NSPoint(x: 665, y: 512))
pulse.line(to: NSPoint(x: 854, y: 512))

let glow = NSShadow()
glow.shadowColor = NSColor(calibratedRed: 0.55, green: 0.85, blue: 1.0, alpha: 0.55)
glow.shadowBlurRadius = 42
glow.set()
NSColor.white.setStroke()
pulse.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
