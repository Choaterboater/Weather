import SwiftUI

/// The Bite Gauge — a marine-instrument radial dial that reads the 0–100
/// fishing score like a barometer: a red→amber→green arc, tick marks, and a
/// brass needle. The app's signature element, replacing a plain number.
struct BiteGauge: View {
    let score: Int

    private let startDeg = 150.0
    private let spanDeg = 240.0

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height * 0.82
            let r = min(size.width * 0.42, size.height * 0.78)

            func point(_ deg: Double, _ radius: Double) -> CGPoint {
                let a = deg * .pi / 180
                return CGPoint(x: cx + cos(a) * radius, y: cy + sin(a) * radius)
            }
            func arc(_ from: Double, _ to: Double, _ color: Color, _ width: Double) {
                var p = Path()
                p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                         startAngle: .degrees(startDeg + spanDeg * from),
                         endAngle: .degrees(startDeg + spanDeg * to),
                         clockwise: false)
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .butt))
            }

            let f = max(0, min(1, Double(score) / 100))

            arc(0, 1, Ink.hullLine, 16)          // track
            arc(0, 0.40, Ink.slack, 16)          // zones
            arc(0.40, 0.65, Ink.brass, 16)
            arc(0.65, 1, Ink.bite, 16)

            for i in 0...10 {                    // ticks
                let deg = startDeg + spanDeg * (Double(i) / 10)
                let long = i % 5 == 0
                var p = Path()
                p.move(to: point(deg, r - 24))
                p.addLine(to: point(deg, r - (long ? 38 : 32)))
                ctx.stroke(p, with: .color(long ? Ink.chart : Ink.chartDim),
                           style: StrokeStyle(lineWidth: long ? 2.5 : 1.5))
            }

            let na = (startDeg + spanDeg * f) * .pi / 180      // needle
            let base1 = CGPoint(x: cx + cos(na + .pi / 2) * 6, y: cy + sin(na + .pi / 2) * 6)
            let base2 = CGPoint(x: cx + cos(na - .pi / 2) * 6, y: cy + sin(na - .pi / 2) * 6)
            var needle = Path()
            needle.move(to: base1)
            needle.addLine(to: point(startDeg + spanDeg * f, r - 30))
            needle.addLine(to: base2)
            needle.closeSubpath()
            ctx.fill(needle, with: .color(Ink.brass))

            ctx.fill(Path(ellipseIn: CGRect(x: cx - 11, y: cy - 11, width: 22, height: 22)),
                     with: .color(Ink.chart))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 5, y: cy - 5, width: 10, height: 10)),
                     with: .color(Ink.abyss))
        }
        .accessibilityLabel("Bite gauge")
        .accessibilityValue("\(score) out of 100")
    }
}
