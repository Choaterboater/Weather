import SwiftUI

struct HourlyForecastView: View {
    let hourly: [HourlyWeatherPoint]
    var now: Date = .now

    /// The next 24 hours from now.
    private var upcoming: [HourlyWeatherPoint] {
        hourly
            .filter { $0.date >= now }
            .prefix(24)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Hourly", systemImage: "clock")
            GlassCard {
                VStack(spacing: 14) {
                    TemperatureChart(samples: hourly.samples(now: now))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(upcoming, id: \.date) { hour in
                                HourCell(hour: hour)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct HourCell: View {
    let hour: HourlyWeatherPoint

    private var time: String {
        hour.date.formatted(.dateTime.hour())
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(time)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Ink.chartDim)
            Image(systemName: hour.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 20, weight: .bold))
            Text(WeatherUnits.wholeTemperature(celsius: hour.temperatureCelsius))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Ink.chart)
            if let precipitationChance = hour.precipitationChance,
               precipitationChance > 0 {
                Text(precipitationChance.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Ink.tide)
            }
        }
    }
}
