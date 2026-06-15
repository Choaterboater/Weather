import SwiftUI
import WeatherKit

struct CurrentConditionsView: View {
    let current: CurrentWeather

    private var temperature: String {
        current.temperature.formatted(.measurement(width: .narrow, usage: .weather))
    }

    private var feelsLike: String {
        current.apparentTemperature.formatted(.measurement(width: .narrow, usage: .weather))
    }

    private var wind: String {
        let speed = current.wind.speed.formatted(.measurement(width: .abbreviated, usage: .general))
        return "\(current.wind.compassDirection.abbreviation) \(speed)"
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(temperature)
                        .font(.system(size: 64, weight: .thin, design: .rounded))
                    Spacer()
                    Image(systemName: current.symbolName)
                        .font(.system(size: 44))
                        .symbolRenderingMode(.multicolor)
                }

                Text(current.condition.description)
                    .font(.title3.weight(.medium))

                Text("Feels like \(feelsLike)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 24) {
                    Metric(label: "Wind", value: wind, systemImage: "wind")
                    Metric(label: "Humidity",
                           value: current.humidity.formatted(.percent.precision(.fractionLength(0))),
                           systemImage: "humidity")
                    Metric(label: "UV", value: "\(current.uvIndex.value)", systemImage: "sun.max")
                }
            }
        }
    }
}

private struct Metric: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
