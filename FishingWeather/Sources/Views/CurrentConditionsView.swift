import SwiftUI

struct CurrentConditionsView: View {
    let current: CurrentConditionsSnapshot

    private var temperature: String {
        WeatherUnits.wholeTemperature(celsius: current.temperatureCelsius)
    }

    private var feelsLike: String {
        WeatherUnits.wholeTemperature(celsius: current.apparentTemperatureCelsius)
    }

    private var wind: String {
        let compass = WeatherUnits.compassAbbreviation(degrees: current.wind.directionDegrees)
        let speed = Measurement(
            value: WeatherUnits.milesPerHour(
                metersPerSecond: current.wind.speedMetersPerSecond
            ),
            unit: UnitSpeed.milesPerHour
        )
        .formatted(.measurement(width: .abbreviated, usage: .asProvided))
        return "\(compass) \(speed)"
    }

    private var humidity: String {
        current.humidityFraction?.formatted(
            .percent.precision(.fractionLength(0))
        ) ?? "—"
    }

    private var dewPoint: String {
        current.dewPointCelsius.map {
            WeatherUnits.wholeTemperature(celsius: $0)
        } ?? "—"
    }

    private var visibility: String {
        current.visibilityMeters.map {
            Measurement(value: $0, unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .general))
        } ?? "—"
    }

    private var uvIndex: String {
        current.uvIndex.map { String($0) } ?? "—"
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

                Text(current.conditionText)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Ink.chart)

                Text("Feels like \(feelsLike)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.chartDim)

                Divider()

                HStack(spacing: 16) {
                    Metric(label: "Wind", value: wind, systemImage: "wind")
                    Metric(label: "Humidity", value: humidity, systemImage: "humidity")
                    Metric(label: "Dew Point", value: dewPoint, systemImage: "drop.fill")
                    Metric(label: "Visibility", value: visibility, systemImage: "eye")
                    Metric(label: "UV", value: uvIndex, systemImage: "sun.max")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current conditions")
        .accessibilityValue("\(temperature), \(current.conditionText). Feels like \(feelsLike). Wind \(wind). Humidity \(humidity). UV index \(uvIndex).")
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
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Ink.chart)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
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
