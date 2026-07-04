import Charts
import SwiftUI
import WeatherKit

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
                colors: [Ink.brass.opacity(0.42), Ink.brass.opacity(0.02)],
                startPoint: .top, endPoint: .bottom
            ))

            LineMark(x: .value("Time", sample.date), y: .value("Pressure", sample.pressureHPa))
                .interpolationMethod(.catmullRom)
                .lineStyle(.init(lineWidth: 2.5))
                .foregroundStyle(Ink.brass)

            RuleMark(x: .value("Now", now))
                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .chartYScale(domain: range)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: .dateTime.hour()).font(.caption2).foregroundStyle(.secondary)
                    }
                }
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
                    colors: [Ink.brass.opacity(0.28), .clear],
                    startPoint: .top, endPoint: .bottom
                ))

            LineMark(x: .value("Time", sample.date), y: .value("Temp", sample.temperature))
                .interpolationMethod(.monotone)
                .lineStyle(.init(lineWidth: 3, lineCap: .round))
                .foregroundStyle(.linearGradient(
                    colors: [Ink.bite, Ink.brass, Ink.slack],
                    startPoint: .leading, endPoint: .trailing
                ))
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))°").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: .dateTime.hour()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 120)
        .accessibilityLabel("Temperature chart for the next 24 hours")
    }
}

/// Wind speed over the next 24 hours as a shaded area, with a dashed gust line
/// and a "now" marker — the shape (building vs. laying down) is what an angler
/// plans around.
struct WindForecastChart: View {
    let samples: [HourSample]
    let now: Date

    private var domainMax: Double {
        let peak = samples.map { max($0.windSpeedMph, $0.windGustMph ?? 0) }.max() ?? 10
        // Floor the ceiling so a calm day doesn't blow the y-axis up to a
        // dramatic-looking 3 mph, and add headroom above the peak gust.
        return max(peak * 1.15, 12)
    }

    private var hasGusts: Bool { samples.contains { $0.windGustMph != nil } }

    var body: some View {
        Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("Time", sample.date),
                    y: .value("Wind", sample.windSpeedMph)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.linearGradient(
                    colors: [Ink.bite.opacity(0.5), Ink.bite.opacity(0.03)],
                    startPoint: .top, endPoint: .bottom
                ))

                LineMark(
                    x: .value("Time", sample.date),
                    y: .value("Wind", sample.windSpeedMph),
                    series: .value("Series", "Sustained")
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(.init(lineWidth: 2.5))
                .foregroundStyle(Ink.bite)
            }

            ForEach(samples) { sample in
                if let gust = sample.windGustMph {
                    LineMark(
                        x: .value("Time", sample.date),
                        y: .value("Gust", gust),
                        series: .value("Series", "Gust")
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(.init(lineWidth: 1.5, dash: [3, 3]))
                    .foregroundStyle(Ink.brass.opacity(0.85))
                }
            }

            RuleMark(x: .value("Now", now))
                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .chartYScale(domain: 0...domainMax)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: .dateTime.hour()).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 130)
        .accessibilityLabel("Wind speed forecast for the next 24 hours\(hasGusts ? ", with gusts" : "")")
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
                    (window.period == .major ? Ink.bite : Ink.brass)
                        .opacity(window.isActive(at: now) ? 0.9 : 0.45)
                )
                .annotation(position: .top, alignment: .center, spacing: 2) {
                    Text(window.period.rawValue)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(window.period == .major ? Ink.bite : Ink.brass)
                }
            }

            RuleMark(x: .value("Now", now))
                .lineStyle(.init(lineWidth: 2))
                .foregroundStyle(.primary.opacity(0.6))
        }
        .chartXScale(domain: dayBounds.start...dayBounds.end)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: .dateTime.hour()).foregroundStyle(.secondary)
                    }
                }
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
                .foregroundStyle(.primary)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(LinearGradient(colors: [Ink.hullLine, Ink.brass], startPoint: .bottom, endPoint: .top))
        .accessibilityLabel("Moon illumination \(Int(phase.illuminationFraction * 100)) percent")
    }
}
