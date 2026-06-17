import Charts
import SwiftUI

/// Barometric pressure over the next hours, with a "now" marker. Pressure trend
/// matters more to the bite than the absolute value, so the shape is the point.
struct PressureTrendChart: View {
    let samples: [HourSample]
    let now: Date

    private var range: ClosedRange<Double> {
        let values = samples.map(\.pressureHPa)
        guard let lo = values.min(), let hi = values.max() else { return 1000...1020 }
        let pad = max((hi - lo) * 0.25, 1.5)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart(samples) { sample in
            AreaMark(
                x: .value("Time", sample.date),
                yStart: .value("min", range.lowerBound),
                yEnd: .value("Pressure", sample.pressureHPa)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.linearGradient(
                colors: [.teal.opacity(0.45), .teal.opacity(0.02)],
                startPoint: .top, endPoint: .bottom
            ))

            LineMark(x: .value("Time", sample.date), y: .value("Pressure", sample.pressureHPa))
                .interpolationMethod(.catmullRom)
                .lineStyle(.init(lineWidth: 2.5))
                .foregroundStyle(.teal)

            RuleMark(x: .value("Now", now))
                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .chartYScale(domain: range)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(Int(v))").font(.caption2) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .frame(height: 130)
        .accessibilityLabel("Pressure trend chart for the next 24 hours")
    }
}

/// 24-hour temperature curve.
struct TemperatureChart: View {
    let samples: [HourSample]

    var body: some View {
        Chart(samples) { sample in
            AreaMark(x: .value("Time", sample.date), y: .value("Temp", sample.temperature))
                .interpolationMethod(.monotone)
                .foregroundStyle(.linearGradient(
                    colors: [.orange.opacity(0.25), .clear],
                    startPoint: .top, endPoint: .bottom
                ))

            LineMark(x: .value("Time", sample.date), y: .value("Temp", sample.temperature))
                .interpolationMethod(.monotone)
                .lineStyle(.init(lineWidth: 3, lineCap: .round))
                .foregroundStyle(.linearGradient(
                    colors: [.orange, .pink, .blue],
                    startPoint: .leading, endPoint: .trailing
                ))
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(Int(v))°") }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .frame(height: 120)
        .accessibilityLabel("Temperature chart for the next 24 hours")
    }
}

/// Today's solunar bite windows as bands across the day, with a "now" marker.
struct BiteWindowsTimeline: View {
    let windows: [BiteWindow]
    let now: Date

    private var dayBounds: (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))
    }

    var body: some View {
        Chart {
            ForEach(windows) { window in
                RectangleMark(
                    xStart: .value("Start", window.start),
                    xEnd: .value("End", window.end),
                    y: .value("Lane", "Bite")
                )
                .cornerRadius(6)
                .foregroundStyle(
                    (window.period == .major ? Color.green : Color.teal)
                        .opacity(window.isActive(at: now) ? 0.85 : 0.45)
                )
                .annotation(position: .top, alignment: .center, spacing: 2) {
                    Text(window.period.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(window.period == .major ? .green : .teal)
                }
            }

            RuleMark(x: .value("Now", now))
                .lineStyle(.init(lineWidth: 2))
                .foregroundStyle(.primary.opacity(0.7))
        }
        .chartXScale(domain: dayBounds.start...dayBounds.end)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .frame(height: 92)
        .accessibilityLabel("Timeline of today's major and minor bite windows")
    }
}

/// Moon illumination as a circular gauge.
struct MoonArc: View {
    let phase: MoonPhase

    var body: some View {
        Gauge(value: phase.illuminationFraction) {
            Image(systemName: phase.symbolName)
        } currentValueLabel: {
            Text(phase.illuminationFraction, format: .percent.precision(.fractionLength(0)))
                .contentTransition(.numericText())
        }
        .gaugeStyle(.accessoryCircular)
        .tint(.linearGradient(colors: [.indigo, .yellow], startPoint: .bottom, endPoint: .top))
        .accessibilityLabel("Moon illumination \(Int(phase.illuminationFraction * 100)) percent")
    }
}
