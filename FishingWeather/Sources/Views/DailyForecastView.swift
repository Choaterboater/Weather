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

    @ScaledMetric private var dayColumnWidth: CGFloat = 56
    @ScaledMetric private var iconColumnWidth: CGFloat = 32
    @ScaledMetric private var precipColumnWidth: CGFloat = 40

    private var weekday: String {
        isFirst ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated))
    }

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

            if day.precipitationChance > 0 {
                Text(day.precipitationChance.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Ink.tide)
                    .frame(width: precipColumnWidth, alignment: .leading)
            } else {
                Color.clear.frame(width: precipColumnWidth)
            }

            Spacer()

            Text(day.lowTemperature.formatted(.measurement(width: .narrow, usage: .weather)))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Ink.chartDim)
            Text(day.highTemperature.formatted(.measurement(width: .narrow, usage: .weather)))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Ink.chart)
        }
        .padding(.vertical, 10)
    }
}
