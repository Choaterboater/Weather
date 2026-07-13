import SwiftUI

struct HourlyForecastView: View {
    let points: [ForecastPoint]
    let timeZone: TimeZone

    @State private var internalSelectedDate: Date?
    @State private var metric: ForecastMetric = .temperature
    @State private var cellScrollDate: Date?
    private let sharedSelectedDate: Binding<Date?>?

    /// Shared-selection initializer used by BiteTime and, next, Pro Forecast.
    init(
        points: [ForecastPoint],
        selectedDate: Binding<Date?>,
        timeZone: TimeZone = .current
    ) {
        self.points = points
        self.timeZone = timeZone
        sharedSelectedDate = selectedDate
        _internalSelectedDate = State(initialValue: nil)
        _cellScrollDate = State(
            initialValue: selectedDate.wrappedValue ?? points.first?.date
        )
    }

    /// Compatibility initializer for the existing Weather dashboard. It still
    /// creates provider-neutral forecast points and owns a real local binding.
    init(hourly: [HourlyWeatherPoint], now: Date = .now) {
        var dates = Set<Date>()
        points = hourly
            .filter { $0.date >= now }
            .sorted { $0.date < $1.date }
            .filter { dates.insert($0.date).inserted }
            .prefix(48)
            .map {
                ForecastPoint(
                    weather: $0,
                    biteScore: nil,
                    tideHeightFeet: nil,
                    tidePhase: nil,
                    solunarWindow: nil
                )
            }
        sharedSelectedDate = nil
        timeZone = .current
        _internalSelectedDate = State(initialValue: points.first?.date)
        _cellScrollDate = State(initialValue: points.first?.date)
    }

    private var selectedDate: Binding<Date?> {
        sharedSelectedDate ?? $internalSelectedDate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Timeline", systemImage: "chart.xyaxis.line")
            GlassCard {
                VStack(spacing: 16) {
                    InteractiveForecastChart(
                        points: points,
                        selectedDate: selectedDate,
                        metric: $metric,
                        timeZone: timeZone
                    )

                    Divider()
                        .overlay(Ink.hullLine)

                    hourlyCells
                }
            }
        }
        .onChange(of: selectedDate.wrappedValue) { _, newValue in
            guard cellScrollDate != newValue else { return }
            cellScrollDate = newValue
        }
    }

    private var hourlyCells: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(points) { point in
                    HourCell(
                        point: point,
                        timeZone: timeZone,
                        isSelected: selectedDate.wrappedValue == point.date
                    ) {
                        guard selectedDate.wrappedValue != point.date else { return }
                        selectedDate.wrappedValue = point.date
                    }
                    .id(point.date)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $cellScrollDate, anchor: .center)
        .accessibilityLabel("Hourly forecast")
    }
}

private struct HourCell: View {
    let point: ForecastPoint
    let timeZone: TimeZone
    let isSelected: Bool
    let select: () -> Void

    @Environment(\.locale) private var locale

    private var time: String {
        ForecastDateFormatting.string(
            from: point.date,
            presentation: .hour,
            timeZone: timeZone,
            locale: locale
        )
    }

    private var wind: String {
        let mph = WeatherUnits.milesPerHour(
            metersPerSecond: point.weather.wind.speedMetersPerSecond
        )
        guard mph.isFinite else { return "wind unavailable" }
        return "\(Int(mph.rounded())) mph wind"
    }

    private var accessibilityValue: String {
        var values = [
            WeatherUnits.wholeTemperature(
                celsius: point.weather.temperatureCelsius,
                locale: locale
            ),
            point.weather.conditionText,
            wind,
        ]
        if let precipitationChance = point.weather.precipitationChance,
           precipitationChance.isFinite {
            values.append(
                "\(precipitationChance.formatted(.percent.precision(.fractionLength(0)))) chance of precipitation"
            )
        }
        if let biteScore = point.biteScore {
            values.append("bite score \(biteScore) out of 100")
        }
        return values.joined(separator: ", ")
    }

    var body: some View {
        Button(action: select) {
            VStack(spacing: 7) {
                Text(time)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(isSelected ? Ink.abyss : Ink.chartDim)

                Image(systemName: point.weather.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 21, weight: .semibold))

                Text(WeatherUnits.wholeTemperature(
                    celsius: point.weather.temperatureCelsius,
                    locale: locale
                ))
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .foregroundStyle(isSelected ? Ink.abyss : Ink.chart)

                if let precipitationChance = point.weather.precipitationChance,
                   precipitationChance.isFinite,
                   precipitationChance > 0 {
                    Label(
                        precipitationChance.formatted(
                            .percent.precision(.fractionLength(0))
                        ),
                        systemImage: "drop.fill"
                    )
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(isSelected ? Ink.abyss : Ink.tide)
                } else if let biteScore = point.biteScore {
                    Text("Bite \(biteScore)")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(isSelected ? Ink.abyss : Ink.bite)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(minWidth: 72, minHeight: 116)
            .background(
                isSelected ? Ink.brass : Ink.hull,
                in: .rect(cornerRadius: 15)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(isSelected ? Ink.brass : Ink.hullLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            ForecastDateFormatting.string(
                from: point.date,
                presentation: .dateTime,
                timeZone: timeZone,
                locale: locale
            )
        )
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Select this hour for forecast details")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
