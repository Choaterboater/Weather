import Charts
import SwiftUI

/// Renders the day's tide curve plus labeled high/low events.
/// Sits in the Fishing tab between the bite-windows card and the pressure card,
/// only when the active spot is saltwater (or no spot is selected and we got data back).
struct TideCard: View {
    let events: [TideEvent]
    let samples: [TideSample]
    let stationName: String?
    let distanceMiles: Double?
    let isLoading: Bool
    var lastError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Tides", systemImage: "water.waves")
            GlassCard {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading tide predictions…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let lastError {
                    Label(lastError, systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if events.isEmpty && samples.isEmpty {
                    Text("No tide station in range.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        chart
                        Divider()
                        eventsList
                        if let stationName {
                            stationFootnote(stationName)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        if samples.count > 1 {
            Chart {
                ForEach(samples) { sample in
                    AreaMark(
                        x: .value("Time", sample.time),
                        y: .value("ft", sample.heightFeet)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Ink.tide.opacity(0.45), Ink.tide.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Time", sample.time),
                        y: .value("ft", sample.heightFeet)
                    )
                    .foregroundStyle(Ink.tide)
                    .interpolationMethod(.catmullRom)
                }
                ForEach(events) { event in
                    if let h = event.heightFeet {
                        PointMark(
                            x: .value("Time", event.time),
                            y: .value("ft", h)
                        )
                        .symbol(.circle)
                        .symbolSize(70)
                        .foregroundStyle(event.kind == .high ? Ink.brass : Ink.tide)
                        .annotation(position: .top, alignment: .center, spacing: 2) {
                            Text(event.kind.label.first.map(String.init) ?? "")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(event.kind == .high ? Ink.brass : Ink.tide)
                        }
                    }
                }
                RuleMark(x: .value("Now", Date.now))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 140)
        }
    }

    private var eventsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(events) { event in
                HStack(spacing: 12) {
                    Image(systemName: event.kind.symbolName)
                        .foregroundStyle(event.kind == .high ? Ink.brass : Ink.tide)
                        .font(.headline)
                        .frame(width: 22)
                    Text(event.kind.label)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(event.time.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                        .monospacedDigit()
                    Text(event.heightFeet.map { String(format: "%.1f ft", $0) } ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
            }
        }
    }

    private func stationFootnote(_ name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "mappin.and.ellipse")
                .font(.caption2)
            Text(name)
                .font(.caption2)
            if let distanceMiles {
                Text("· \(Int(distanceMiles)) mi")
                    .font(.caption2)
            }
            Spacer()
            Text("NOAA")
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.secondary)
    }
}
