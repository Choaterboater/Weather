import Charts
import SwiftUI

/// Barometric pressure over the selected hours, with a selected-time marker.
/// Pressure trend matters more than the absolute value, so the shape is the point.
struct PressureTrendChart: View {
    let samples: [HourSample]
    let referenceDate: Date
    var timeZone: TimeZone = .current

    private var pressureSamples: [HourSample] {
        samples.filter { $0.pressureHPa != nil }
    }

    private var range: ClosedRange<Double>? {
        let values = pressureSamples.compactMap(\.pressureHPa)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        let pad = max((hi - lo) * 0.25, 1.5)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Group {
            if let range {
                Chart {
                    ForEach(pressureSamples) { sample in
                        if let pressure = sample.pressureHPa {
                            AreaMark(
                                x: .value("Time", sample.date),
                                yStart: .value("min", range.lowerBound),
                                yEnd: .value("Pressure", pressure)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.linearGradient(
                                colors: [Ink.brass.opacity(0.42), Ink.brass.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            ))

                            LineMark(
                                x: .value("Time", sample.date),
                                y: .value("Pressure", pressure)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(.init(lineWidth: 2.5))
                            .foregroundStyle(Ink.brass)
                        }
                    }

                    RuleMark(x: .value("Selected time", referenceDate))
                        .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .chartYScale(domain: range)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Ink.hullLine.opacity(0.3))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v))")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Ink.chartDim)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                        AxisGridLine().foregroundStyle(Ink.hullLine.opacity(0.3))
                        AxisValueLabel {
                            if let d = value.as(Date.self) {
                                Text(FishingDetailDateFormatting.time(
                                    d,
                                    timeZone: timeZone
                                ))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Ink.chartDim)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "barometer")
                        .foregroundStyle(Ink.chartDim)
                    Text("Pressure unavailable")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 130)
        .accessibilityLabel(
            pressureSamples.isEmpty
                ? "Pressure trend unavailable"
                : "Pressure trend chart for the next 24 hours"
        )
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
                AxisGridLine().foregroundStyle(Ink.hullLine.opacity(0.3))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisGridLine().foregroundStyle(Ink.hullLine.opacity(0.3))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: .dateTime.hour())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    }
                }
            }
        }
        .frame(height: 130)
        .accessibilityLabel("Wind speed forecast for the next 24 hours\(hasGusts ? ", with gusts" : "")")
    }
}

/// Selected-day solunar bite windows with a selected-time marker.
struct BiteWindowsTimeline: View {
    let windows: [BiteWindow]
    let referenceDate: Date
    let timeZone: TimeZone

    private var dayBounds: (start: Date, end: Date) {
        let bounds = FishingDetailDateFormatting.dayBounds(
            containing: referenceDate,
            timeZone: timeZone
        )
        return (bounds.start, bounds.end)
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
                        .opacity(window.isActive(at: referenceDate) ? 0.9 : 0.45)
                )
                .annotation(position: .top, alignment: .center, spacing: 2) {
                    Text(window.period.rawValue)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(window.period == .major ? Ink.bite : Ink.brass)
                }
            }

            RuleMark(x: .value("Selected time", referenceDate))
                .lineStyle(.init(lineWidth: 2))
                .foregroundStyle(Ink.chartDim)
        }
        .chartXScale(domain: dayBounds.start...dayBounds.end)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                AxisGridLine().foregroundStyle(Ink.hullLine.opacity(0.3))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(FishingDetailDateFormatting.time(
                            d,
                            timeZone: timeZone
                        ))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    }
                }
            }
        }
        .frame(height: 92)
        .accessibilityLabel("Timeline of the selected forecast day's major and minor bite windows")
    }
}

/// Moon illumination as a circular gauge.
struct MoonArc: View {
    let phase: LunarPhase

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
