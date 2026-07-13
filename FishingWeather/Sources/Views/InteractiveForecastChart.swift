import Accessibility
import Charts
import Foundation
import SwiftUI

/// A shared, scrubbable forecast timeline. Raw drag positions are kept local;
/// only snapped provider hours are written to the cross-screen selection.
struct InteractiveForecastChart: View {
    let points: [ForecastPoint]
    let timeZone: TimeZone
    @Binding var selectedDate: Date?
    @Binding var metric: ForecastMetric

    @Environment(\.locale) private var locale
    @State private var rawSelection: Date?
    @State private var scrollDate: Date

    init(
        points: [ForecastPoint],
        selectedDate: Binding<Date?>,
        metric: Binding<ForecastMetric>,
        timeZone: TimeZone = .current
    ) {
        self.points = points
        self.timeZone = timeZone
        _selectedDate = selectedDate
        _metric = metric
        let start = selectedDate.wrappedValue ?? points.first?.date ?? .now
        _rawSelection = State(initialValue: start)
        _scrollDate = State(initialValue: start)
    }

    private var selectedPoint: ForecastPoint? {
        selectedDate.flatMap { ForecastSelection.nearest(to: $0, in: points) }
            ?? points.first
    }

    private var plottableValues: [Double] {
        points.compactMap { metric.plotValue(for: $0, locale: locale) }
    }

    private var yDomain: ClosedRange<Double> {
        if metric == .precipitation || metric == .biteScore {
            return 0...100
        }
        guard let low = plottableValues.min(),
              let high = plottableValues.max() else {
            return 0...1
        }
        let padding = max((high - low) * 0.18, metric.minimumPadding)
        let lowerBound = metric == .wind ? max(0, low - padding) : low - padding
        return lowerBound...(high + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            metricPicker

            if plottableValues.isEmpty {
                ContentUnavailableView(
                    "\(metric.title) unavailable",
                    systemImage: metric.symbolName,
                    description: Text("This weather source did not report \(metric.title.lowercased()).")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                chart
                detailStrip
            }
        }
        .onChange(of: rawSelection) { _, newValue in
            let snapped = ForecastSelection.snappedDate(
                for: newValue,
                current: selectedDate,
                in: points
            )
            guard snapped != selectedDate else { return }
            selectedDate = snapped
        }
        .onChange(of: selectedDate) { _, newValue in
            guard let newValue else { return }
            rawSelection = newValue
            scrollDate = newValue
        }
        .onChange(of: metric) {
            rawSelection = selectedDate
        }
    }

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ForecastMetric.allCases) { option in
                    Button {
                        metric = option
                    } label: {
                        Label(option.title, systemImage: option.symbolName)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(option == metric ? Ink.abyss : Ink.chartDim)
                    .background(
                        option == metric ? option.tint : Ink.hull,
                        in: .capsule
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                option == metric ? option.tint : Ink.hullLine,
                                lineWidth: 1
                            )
                    )
                    .accessibilityAddTraits(option == metric ? .isSelected : [])
                }
            }
        }
        .accessibilityLabel("Forecast metric")
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.chart)
                Spacer()
                Text(metric.unitLabel(locale: locale))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.chartDim)
            }

            Chart {
                ForEach(points) { point in
                    if let value = metric.plotValue(for: point, locale: locale) {
                        AreaMark(
                            x: .value("Time", point.date),
                            yStart: .value("Baseline", yDomain.lowerBound),
                            yEnd: .value(metric.title, value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            .linearGradient(
                                colors: [metric.tint.opacity(0.34), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .accessibilityHidden(true)

                        LineMark(
                            x: .value("Time", point.date),
                            y: .value(metric.title, value)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(.init(lineWidth: 3, lineCap: .round))
                        .foregroundStyle(metric.tint)
                        .accessibilityLabel(
                            formattedDateTime(point.date)
                        )
                        .accessibilityValue(
                            metric.formattedValue(for: point, locale: locale)
                                ?? "Unavailable"
                        )
                    }
                }

                if let selectedPoint,
                   let value = metric.plotValue(for: selectedPoint, locale: locale) {
                    RuleMark(x: .value("Selected hour", selectedPoint.date))
                        .lineStyle(.init(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(Ink.chart.opacity(0.8))
                        .accessibilityHidden(true)

                    PointMark(
                        x: .value("Selected hour", selectedPoint.date),
                        y: .value(metric.title, value)
                    )
                    .symbolSize(90)
                    .foregroundStyle(Ink.chart)
                    .accessibilityHidden(true)
                }
            }
            .chartYScale(domain: yDomain)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 12 * 3_600)
            .chartScrollPosition(x: $scrollDate)
            .chartXSelection(value: $rawSelection)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    AxisGridLine().foregroundStyle(Ink.hullLine.opacity(0.45))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(ForecastDateFormatting.string(
                                from: date,
                                presentation: .hour,
                                timeZone: timeZone,
                                locale: locale
                            ))
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .foregroundStyle(Ink.chartDim)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Ink.hullLine.opacity(0.45))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(metric.axisLabel(number, locale: locale))
                                .font(.system(.caption2, design: .monospaced, weight: .medium))
                                .foregroundStyle(Ink.chartDim)
                        }
                    }
                }
            }
            .frame(height: 228)
            .accessibilityChartDescriptor(
                ForecastChartAccessibilityDescriptor(
                    points: points,
                    metric: metric,
                    locale: locale,
                    range: yDomain,
                    timeZone: timeZone
                )
            )
            .accessibilityLabel("Interactive \(metric.title.lowercased()) forecast")
            .accessibilityHint("Swipe up or down to move one forecast hour.")
            .accessibilityAdjustableAction(moveSelection)
        }
    }

    @ViewBuilder
    private var detailStrip: some View {
        if let point = selectedPoint {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formattedDateTime(point.date))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Ink.chart)
                        Text(point.weather.conditionText)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Ink.chartDim)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(metric.formattedValue(for: point, locale: locale) ?? "—")
                            .font(.system(.title3, design: .monospaced, weight: .semibold))
                            .foregroundStyle(metric.tint)
                        Text(metric.title)
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(Ink.chartDim)
                    }
                }

                Divider()
                    .overlay(Ink.hullLine)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading),
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForecastDetailMetric(
                        label: "Temperature",
                        value: ForecastMetric.temperature.formattedValue(
                            for: point,
                            locale: locale
                        ) ?? "Unavailable"
                    )
                    ForecastDetailMetric(
                        label: "Precipitation",
                        value: ForecastMetric.precipitation.formattedValue(
                            for: point,
                            locale: locale
                        ) ?? "Unavailable"
                    )
                    ForecastDetailMetric(
                        label: "Wind",
                        value: windDetail(point)
                    )
                    ForecastDetailMetric(
                        label: "Pressure",
                        value: pressureDetail(point)
                    )
                    ForecastDetailMetric(
                        label: "Bite",
                        value: biteDetail(point)
                    )
                    ForecastDetailMetric(
                        label: "Water",
                        value: tideDetail(point)
                    )
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 64)
            .background(Ink.hull.opacity(0.92), in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Ink.hullLine, lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
        }
    }

    private func windDetail(_ point: ForecastPoint) -> String {
        let sustained = WeatherUnits.milesPerHour(
            metersPerSecond: point.weather.wind.speedMetersPerSecond
        )
        guard sustained.isFinite else { return "Unavailable" }
        let compass = WeatherUnits.compassAbbreviation(
            degrees: point.weather.wind.directionDegrees
        )
        if let gust = point.weather.wind.gustMetersPerSecond,
           gust.isFinite {
            let gustMPH = WeatherUnits.milesPerHour(metersPerSecond: gust)
            return "\(compass) \(Int(sustained.rounded())) mph · gust \(Int(gustMPH.rounded())) mph"
        }
        return "\(compass) \(Int(sustained.rounded())) mph"
    }

    private func pressureDetail(_ point: ForecastPoint) -> String {
        guard let pressure = point.weather.pressureHPa,
              pressure.isFinite else {
            return "Unavailable"
        }
        let trend = point.pressureTendency.map { " · \($0.label.lowercased())" }
            ?? ""
        return "\(Int(pressure.rounded())) hPa\(trend)"
    }

    private func biteDetail(_ point: ForecastPoint) -> String {
        guard let score = point.biteScore else { return "Unavailable" }
        let rating: String = switch score {
        case 85...: "Excellent"
        case 70..<85: "Strong"
        case 50..<70: "Fair"
        case 30..<50: "Tough"
        default: "Poor"
        }
        return "\(score) / 100 · \(rating)"
    }

    private func tideDetail(_ point: ForecastPoint) -> String {
        guard let height = point.tideHeightFeet else { return "Unavailable" }
        var value = String(format: "%.1f ft", height)
        if let phase = point.tidePhase {
            value += " · \(phase.lowercased())"
        }
        if let turn = point.nextTideTurn {
            value += " · \(turn.kind.label.lowercased()) \(formattedTime(turn.time))"
        }
        return value
    }

    private func formattedDateTime(_ date: Date) -> String {
        ForecastDateFormatting.string(
            from: date,
            presentation: .dateTime,
            timeZone: timeZone,
            locale: locale
        )
    }

    private func formattedTime(_ date: Date) -> String {
        ForecastDateFormatting.string(
            from: date,
            presentation: .time,
            timeZone: timeZone,
            locale: locale
        )
    }

    private func moveSelection(_ direction: AccessibilityAdjustmentDirection) {
        guard !points.isEmpty else { return }
        let current = selectedPoint?.date ?? points[0].date
        let index = points.firstIndex { $0.date == current } ?? 0
        let nextIndex: Int
        switch direction {
        case .increment:
            nextIndex = min(index + 1, points.count - 1)
        case .decrement:
            nextIndex = max(index - 1, 0)
        @unknown default:
            return
        }
        let next = points[nextIndex].date
        guard next != selectedDate else { return }
        selectedDate = next
    }
}

private struct ForecastDetailMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(Ink.chartDim)
            Text(value)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(Ink.chart)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Supplies VoiceOver's Audio Graph and non-visual point table with the same
/// values and explicit units shown by the visual chart.
private struct ForecastChartAccessibilityDescriptor: AXChartDescriptorRepresentable {
    let points: [ForecastPoint]
    let metric: ForecastMetric
    let locale: Locale
    let range: ClosedRange<Double>
    let timeZone: TimeZone

    func makeChartDescriptor() -> AXChartDescriptor {
        let values = points.compactMap { point -> (ForecastPoint, Double)? in
            metric.plotValue(for: point, locale: locale).map { (point, $0) }
        }
        let first = values.first?.0.date.timeIntervalSince1970 ?? 0
        let last = values.last?.0.date.timeIntervalSince1970 ?? first
        let xRange = first == last
            ? (first - 1_800)...(last + 1_800)
            : first...last
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Time",
            range: xRange,
            gridlinePositions: [],
            valueDescriptionProvider: { value in
                ForecastDateFormatting.string(
                    from: Date(timeIntervalSince1970: value),
                    presentation: .dateTime,
                    timeZone: timeZone,
                    locale: locale
                )
            }
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "\(metric.title), \(metric.unitLabel(locale: locale))",
            range: range,
            gridlinePositions: [],
            valueDescriptionProvider: { value in
                metric.accessibilityAxisLabel(value, locale: locale)
            }
        )
        let dataPoints = values.map { point, value in
            AXDataPoint(
                x: point.date.timeIntervalSince1970,
                y: value,
                label: ForecastDateFormatting.string(
                    from: point.date,
                    presentation: .dateTime,
                    timeZone: timeZone,
                    locale: locale
                )
            )
        }
        let series = AXDataSeriesDescriptor(
            name: metric.title,
            isContinuous: true,
            dataPoints: dataPoints
        )
        return AXChartDescriptor(
            title: "Hourly \(metric.title)",
            summary: "Hourly \(metric.title.lowercased()) forecast with \(values.count) time and value pairs.",
            xAxis: xAxis,
            yAxis: yAxis,
            series: [series]
        )
    }
}

enum ForecastDatePresentation {
    case hour
    case time
    case dateTime
}

/// Uses the forecast location's time zone for every visible and VoiceOver date
/// string. Date.FormatStyle's `timeZone(_:)` method configures a displayed
/// time-zone symbol; the concrete zone is assigned through the style property.
enum ForecastDateFormatting {
    static func string(
        from date: Date,
        presentation: ForecastDatePresentation,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        var style: Date.FormatStyle
        switch presentation {
        case .hour:
            style = .dateTime.hour()
        case .time:
            style = .dateTime.hour().minute()
        case .dateTime:
            style = .dateTime
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        }
        style.timeZone = timeZone
        style.locale = locale
        return date.formatted(style)
    }
}

private extension ForecastMetric {
    var title: String {
        switch self {
        case .temperature: "Temperature"
        case .wind: "Wind"
        case .pressure: "Pressure"
        case .precipitation: "Precipitation"
        case .biteScore: "Bite score"
        }
    }

    var symbolName: String {
        switch self {
        case .temperature: "thermometer.medium"
        case .wind: "wind"
        case .pressure: "barometer"
        case .precipitation: "drop.fill"
        case .biteScore: "fish.fill"
        }
    }

    var tint: Color {
        switch self {
        case .temperature: Ink.brass
        case .wind: Ink.tide
        case .pressure: Ink.bite
        case .precipitation: .cyan
        case .biteScore: Ink.bite
        }
    }

    var minimumPadding: Double {
        switch self {
        case .temperature: 2
        case .wind: 1
        case .pressure: 1.5
        case .precipitation: 5
        case .biteScore: 5
        }
    }

    func plotValue(for point: ForecastPoint, locale: Locale) -> Double? {
        switch self {
        case .temperature:
            let unit = preferredTemperatureUnit(locale: locale)
            let value = Measurement(
                value: point.weather.temperatureCelsius,
                unit: UnitTemperature.celsius
            ).converted(to: unit).value
            return value.isFinite ? value : nil
        case .wind:
            let value = WeatherUnits.milesPerHour(
                metersPerSecond: point.weather.wind.speedMetersPerSecond
            )
            return value.isFinite ? value : nil
        case .pressure:
            return point.weather.pressureHPa.flatMap { $0.isFinite ? $0 : nil }
        case .precipitation:
            return point.weather.precipitationChance.flatMap {
                let percent = $0 * 100
                return percent.isFinite ? min(max(percent, 0), 100) : nil
            }
        case .biteScore:
            return point.biteScore.map(Double.init)
        }
    }

    func unitLabel(locale: Locale) -> String {
        switch self {
        case .temperature:
            preferredTemperatureUnit(locale: locale) == .fahrenheit ? "°F" : "°C"
        case .wind: "mph"
        case .pressure: "hPa"
        case .precipitation: "% chance"
        case .biteScore: "points / 100"
        }
    }

    func formattedValue(for point: ForecastPoint, locale: Locale) -> String? {
        guard let value = plotValue(for: point, locale: locale) else { return nil }
        switch self {
        case .temperature:
            return "\(Int(value.rounded()))\(unitLabel(locale: locale))"
        case .wind:
            return "\(Int(value.rounded())) mph"
        case .pressure:
            return "\(Int(value.rounded())) hPa"
        case .precipitation:
            return "\(Int(value.rounded()))% chance"
        case .biteScore:
            return "\(Int(value.rounded())) / 100"
        }
    }

    func axisLabel(_ value: Double, locale: Locale) -> String {
        switch self {
        case .temperature:
            "\(Int(value.rounded()))°"
        case .wind:
            "\(Int(value.rounded()))"
        case .pressure:
            "\(Int(value.rounded()))"
        case .precipitation, .biteScore:
            "\(Int(value.rounded()))"
        }
    }

    func accessibilityAxisLabel(_ value: Double, locale: Locale) -> String {
        let whole = Int(value.rounded())
        switch self {
        case .temperature:
            let scale = preferredTemperatureUnit(locale: locale) == .fahrenheit
                ? "Fahrenheit"
                : "Celsius"
            return "\(whole) degrees \(scale)"
        case .wind:
            return "\(whole) miles per hour"
        case .pressure:
            return "\(whole) hectopascals"
        case .precipitation:
            return "\(whole) percent chance"
        case .biteScore:
            return "\(whole) points out of 100"
        }
    }

    private func preferredTemperatureUnit(locale: Locale) -> UnitTemperature {
        locale.measurementSystem == .us ? .fahrenheit : .celsius
    }
}
