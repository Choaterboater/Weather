import Charts
import SwiftUI

/// Renders the day's tide curve plus labeled high/low events.
/// Sits in the Fishing tab between the bite-windows card and the pressure card,
/// only when the active spot is saltwater (or no spot is selected and we got data back).
struct TideCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    let events: [TideEvent]
    let samples: [TideSample]
    let stationName: String?
    let distanceMiles: Double?
    let isLoading: Bool
    var lastError: String? = nil
    var referenceDate: Date = .now

    private var chartDomain: ClosedRange<Date> {
        Self.visibleChartDomain(
            events: events,
            samples: samples,
            referenceDate: referenceDate
        ) ?? referenceDate...referenceDate
    }

    private var chartSamples: [TideSample] {
        Self.visibleSamples(samples, in: chartDomain)
    }

    private var chartEvents: [TideEvent] {
        events.filter { chartDomain.contains($0.time) }
    }

    /// Four centered labels preserve complete short times at the chart edges.
    private var chartTickDates: [Date] {
        Self.chartTickDates(in: chartDomain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Tides", systemImage: "water.waves")
            GlassCard {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading tide predictions…")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(Ink.chartDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let lastError {
                    Label(lastError, systemImage: "wifi.slash")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Ink.chartDim)
                } else if events.isEmpty && samples.isEmpty {
                    Text("No tide station in range.")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Ink.chartDim)
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
        if chartSamples.count > 1 {
            Chart {
                ForEach(chartSamples) { sample in
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
                ForEach(chartEvents) { event in
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
                                .font(.system(.caption2, design: .rounded, weight: .bold))
                                .foregroundStyle(event.kind == .high ? Ink.brass : Ink.tide)
                        }
                    }
                }
                if Self.shouldShowReferenceDate(referenceDate, in: chartDomain) {
                    RuleMark(x: .value("Selected time", referenceDate))
                        .foregroundStyle(Ink.hullLine.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXScale(domain: chartDomain)
            .chartXAxis {
                AxisMarks(values: chartTickDates) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(chartTimeLabel(date))
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let height = value.as(Double.self) {
                            Text(height.formatted(.number.precision(.fractionLength(1))))
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 184 : 140)
            .dynamicTypeSize(...DynamicTypeSize.large)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("bitetime.tideChart")
            .accessibilityLabel("Tide forecast chart")
            .accessibilityValue(chartAccessibilitySummary)
        }
    }

    private var chartAccessibilitySummary: String {
        var details = [
            "From \(shortTime(chartDomain.lowerBound)) to \(shortTime(chartDomain.upperBound))"
        ]
        if !chartEvents.isEmpty {
            let eventDetails = chartEvents.map { event in
                var description = "\(event.kind.label) at \(shortTime(event.time))"
                if let height = event.heightFeet {
                    description += ", \(height.formatted(.number.precision(.fractionLength(1)))) feet"
                }
                return description
            }
            details.append(eventDetails.joined(separator: "; "))
        }
        if Self.shouldShowReferenceDate(referenceDate, in: chartDomain) {
            details.append("Selected time \(shortTime(referenceDate))")
        }
        return details.joined(separator: ". ")
    }

    private func shortTime(_ date: Date) -> String {
        Self.eventTimeLabel(date, locale: locale, timeZone: timeZone)
    }

    private func chartTimeLabel(_ date: Date) -> String {
        Self.chartTimeLabel(date, locale: locale, timeZone: timeZone)
    }

    /// Localized hour-only axis labels remain legible at the chart edges.
    nonisolated static func chartTimeLabel(
        _ date: Date,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("ha")
        return formatter.string(from: date)
    }

    /// Event rows, chart summaries, and injected preview time zones all share
    /// this formatter so one tide instant cannot display as two local times.
    nonisolated static func eventTimeLabel(
        _ date: Date,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    nonisolated static func visibleChartDomain(
        events: [TideEvent],
        samples: [TideSample],
        referenceDate: Date
    ) -> ClosedRange<Date>? {
        let eventTimes = events.map(\.time)
        if let firstEvent = eventTimes.min(),
           let lastEvent = eventTimes.max() {
            let padding: TimeInterval = 3 * 3_600
            let lowerBound = firstEvent.addingTimeInterval(-padding)
            let upperBound = lastEvent.addingTimeInterval(padding)
            return lowerBound...upperBound
        }

        guard !samples.isEmpty else { return nil }
        let halfDay: TimeInterval = 12 * 3_600
        let lowerBound = referenceDate.addingTimeInterval(-halfDay)
        let upperBound = referenceDate.addingTimeInterval(halfDay)
        return lowerBound...upperBound
    }

    nonisolated static func visibleSamples(
        _ samples: [TideSample],
        in domain: ClosedRange<Date>
    ) -> [TideSample] {
        samples.filter { domain.contains($0.time) }
    }

    nonisolated static func chartTickDates(
        in domain: ClosedRange<Date>
    ) -> [Date] {
        let duration = domain.upperBound.timeIntervalSince(domain.lowerBound)
        return (0..<4).map { index in
            domain.lowerBound.addingTimeInterval(
                duration * (Double(index) + 0.5) / 4
            )
        }
    }

    nonisolated static func shouldShowReferenceDate(
        _ referenceDate: Date,
        in domain: ClosedRange<Date>
    ) -> Bool {
        domain.contains(referenceDate)
    }

    private var eventsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(events) { event in
                eventRow(event)
            }
        }
    }

    private func eventRow(_ event: TideEvent) -> some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            Image(systemName: event.kind.symbolName)
                .foregroundStyle(event.kind == .high ? Ink.brass : Ink.tide)
                .font(.headline.weight(.semibold))
                .frame(width: 22)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    eventLabel(event)
                    eventTime(event)
                    eventHeight(event)
                }
            } else {
                eventLabel(event)
                Spacer()
                eventTime(event)
                eventHeight(event)
                    .frame(minWidth: 56, alignment: .trailing)
            }
        }
    }

    private func eventLabel(_ event: TideEvent) -> some View {
        Text(event.kind.label)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(Ink.chart)
    }

    private func eventTime(_ event: TideEvent) -> some View {
        Text(Self.eventTimeLabel(event.time, locale: locale, timeZone: timeZone))
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Ink.chart)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func eventHeight(_ event: TideEvent) -> some View {
        Text(event.heightFeet.map { String(format: "%.1f ft", $0) } ?? "—")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Ink.chartDim)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func stationFootnote(_ name: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    Label(name, systemImage: "mappin.and.ellipse")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                    if let distanceMiles {
                        Text("\(Int(distanceMiles)) mi away")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                    }
                    Text("Data: NOAA")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(name)
                    if let distanceMiles {
                        Text("· \(Int(distanceMiles)) mi")
                            .monospacedDigit()
                    }
                    Spacer()
                    Text("NOAA")
                }
                .font(.system(.caption2, design: .rounded, weight: .semibold))
            }
        }
        .foregroundStyle(Ink.chartDim)
    }
}
