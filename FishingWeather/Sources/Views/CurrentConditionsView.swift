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
                        .font(.system(size: 64, weight: .light, design: .monospaced))
                        .foregroundStyle(Ink.chart)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Spacer()
                    Image(systemName: current.symbolName)
                        .font(.largeTitle)
                        .imageScale(.large)
                        .symbolRenderingMode(.multicolor)
                        .symbolEffect(.bounce, options: .nonRepeating)
                        .accessibilityHidden(true)
                }

                Text(current.condition.description)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Ink.chart)

                Text("Feels like \(feelsLike)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Ink.chartDim)

                Divider()

                HStack(spacing: 16) {
                    Metric(label: "Wind", value: wind, systemImage: "wind")
                    Metric(label: "Humidity",
                           value: current.humidity.formatted(.percent.precision(.fractionLength(0))),
                           systemImage: "humidity")
                    Metric(label: "UV", value: "\(current.uvIndex.value)", systemImage: "sun.max")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current conditions")
        .accessibilityValue("\(temperature), \(current.condition.description). Feels like \(feelsLike). Wind \(wind). Humidity \(current.humidity.formatted(.percent.precision(.fractionLength(0)))). UV index \(current.uvIndex.value).")
    }
}

private struct Metric: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(Ink.chartDim)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Ink.chart)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Ink.chartDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}
