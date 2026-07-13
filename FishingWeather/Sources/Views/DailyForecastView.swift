import Foundation
import SwiftUI

struct DailyForecastView: View {
    let daily: [DailyWeatherPoint]
    let timeZoneIdentifier: String
    let now: Date

    init(
        daily: [DailyWeatherPoint],
        timeZoneIdentifier: String,
        now: Date = .now
    ) {
        self.daily = daily
        self.timeZoneIdentifier = timeZoneIdentifier
        self.now = now
    }

    private var days: [DailyWeatherPoint] {
        daily.prefix(10).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "10-Day", systemImage: "calendar")
            GlassCard {
                VStack(spacing: 0) {
                    ForEach(days, id: \.date) { day in
                        DayRow(
                            day: day,
                            weekday: Self.dayLabel(
                                for: day.date,
                                now: now,
                                timeZoneIdentifier: timeZoneIdentifier
                            )
                        )
                        if day.date != days.last?.date {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    nonisolated static func dayLabel(
        for date: Date,
        now: Date,
        timeZoneIdentifier: String,
        locale: Locale = .current
    ) -> String {
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale

        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }
}

private struct DayRow: View {
    let day: DailyWeatherPoint
    let weekday: String

    @Environment(\.locale) private var locale
    @ScaledMetric private var dayColumnWidth: CGFloat = 56
    @ScaledMetric private var iconColumnWidth: CGFloat = 32
    @ScaledMetric private var precipColumnWidth: CGFloat = 40

    var body: some View {
        HStack {
            Text(weekday)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Ink.chart)
                .lineLimit(1)
                .frame(width: dayColumnWidth, alignment: .leading)

            Image(systemName: day.symbolName)
                .symbolRenderingMode(.multicolor)
                .frame(width: iconColumnWidth)

            if let precipitationChance = day.precipitationChance,
               precipitationChance > 0 {
                Text(precipitationChance.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.tide)
                    .frame(width: precipColumnWidth, alignment: .leading)
            } else {
                Color.clear.frame(width: precipColumnWidth)
            }

            Spacer()

            Text(WeatherUnits.wholeTemperature(celsius: day.lowCelsius))
                .font(.system(.subheadline, design: .monospaced, weight: .medium))
                .foregroundStyle(Ink.chartDim)
            Text(WeatherUnits.wholeTemperature(celsius: day.highCelsius))
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                .foregroundStyle(Ink.chart)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var values = [
            weekday,
            day.conditionText,
            "low \(WeatherUnits.wholeTemperature(celsius: day.lowCelsius, locale: locale))",
            "high \(WeatherUnits.wholeTemperature(celsius: day.highCelsius, locale: locale))",
        ]
        if let chance = day.precipitationChance, chance.isFinite {
            values.append(
                "\(chance.formatted(.percent.precision(.fractionLength(0)))) chance of precipitation"
            )
        }
        return values.joined(separator: ", ")
    }
}
