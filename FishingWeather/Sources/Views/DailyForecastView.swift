import SwiftUI
import WeatherKit

struct DailyForecastView: View {
    let daily: Forecast<DayWeather>

    private var days: [DayWeather] {
        daily.forecast.prefix(10).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "10-Day", systemImage: "calendar")
            GlassCard {
                VStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.date) { index, day in
                        DayRow(day: day, isFirst: index == 0)
                        if day.date != days.last?.date {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct DayRow: View {
    let day: DayWeather
    let isFirst: Bool

    private var weekday: String {
        isFirst ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated))
    }

    var body: some View {
        HStack {
            Text(weekday)
                .font(.body.weight(.medium))
                .frame(width: 56, alignment: .leading)

            Image(systemName: day.symbolName)
                .symbolRenderingMode(.multicolor)
                .frame(width: 32)

            if day.precipitationChance > 0 {
                Text(day.precipitationChance.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption)
                    .foregroundStyle(.cyan)
                    .frame(width: 40, alignment: .leading)
            } else {
                Spacer().frame(width: 40)
            }

            Spacer()

            Text(day.lowTemperature.formatted(.measurement(width: .narrow, usage: .weather)))
                .foregroundStyle(.secondary)
            Text(day.highTemperature.formatted(.measurement(width: .narrow, usage: .weather)))
        }
        .padding(.vertical, 10)
    }
}
