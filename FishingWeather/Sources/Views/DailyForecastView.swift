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

    @ScaledMetric private var dayColumnWidth: CGFloat = 56
    @ScaledMetric private var iconColumnWidth: CGFloat = 32
    @ScaledMetric private var precipColumnWidth: CGFloat = 40

    var body: some View {
        HStack {
            Text(weekday)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Ink.chart)
                .lineLimit(1)
                .frame(width: dayColumnWidth, alignment: .leading)

            Image(systemName: day.symbolName)
                .symbolRenderingMode(.multicolor)
                .frame(width: iconColumnWidth)

            if let precipitationChance = day.precipitationChance,
               precipitationChance > 0 {
                Text(precipitationChance.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Ink.tide)
                    .frame(width: precipColumnWidth, alignment: .leading)
            } else {
                Color.clear.frame(width: precipColumnWidth)
            }

            Spacer()

            Text(WeatherUnits.wholeTemperature(celsius: day.lowCelsius))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Ink.chartDim)
            Text(WeatherUnits.wholeTemperature(celsius: day.highCelsius))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Ink.chart)
        }
        .padding(.vertical, 10)
    }
}
