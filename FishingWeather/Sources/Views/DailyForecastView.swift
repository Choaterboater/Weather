import SwiftUI

struct DailyForecastView: View {
    let daily: [DailyWeatherPoint]

    private var days: [DailyWeatherPoint] {
        daily.prefix(10).map { $0 }
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
    let day: DailyWeatherPoint
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
