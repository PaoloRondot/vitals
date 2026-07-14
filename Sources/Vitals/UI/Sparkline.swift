import SwiftUI

/// Minimal line-plus-fill history chart drawn with Canvas.
struct Sparkline: View {
    var values: [Double]
    /// Fixed scale ceiling (e.g. 1.0 for percentages); nil auto-scales to the max.
    var maxValue: Double?
    var color: Color = .accentColor

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let ceiling = max(maxValue ?? (values.max() ?? 1), 0.0001)
            let stepX = size.width / CGFloat(values.count - 1)

            func point(_ index: Int) -> CGPoint {
                CGPoint(x: CGFloat(index) * stepX,
                        y: size.height * (1 - CGFloat(min(values[index] / ceiling, 1))))
            }

            var line = Path()
            line.move(to: point(0))
            for index in 1..<values.count {
                line.addLine(to: point(index))
            }

            var fill = line
            fill.addLine(to: CGPoint(x: CGFloat(values.count - 1) * stepX, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()

            context.fill(fill, with: .color(color.opacity(0.15)))
            context.stroke(line, with: .color(color), lineWidth: 1.5)
        }
    }
}
