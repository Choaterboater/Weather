import SwiftUI

struct CurrentConditionsView: View {
    let current: CurrentConditionsSnapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    private var metricColumns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: dynamicTypeSize.isAccessibilitySize ? 140 : 56
                ),
                spacing: 8,
                alignment: .top
            ),
        ]
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(temperature)
                        .font(.system(.largeTitle, design: .rounded, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(Ink.chart)
                        .contentTransition(.numericText())
                    Spacer()
                    Image(systemName: current.symbolName)
                        .font(.largeTitle)
                        .imageScale(.large)
                        .symbolRenderingMode(.multicolor)
                        .symbolEffect(
                            .bounce,
                            options: .nonRepeating,
                            isActive: !reduceMotion
                        )
                        .accessibilityHidden(true)
                }

                Text(current.conditionText)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Ink.chart)

                Text("Feels like \(feelsLike)")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Ink.chartDim)

                Divider()

                LazyVGrid(
                    columns: metricColumns,
                    alignment: .leading,
                    spacing: 12
                ) {
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 8) {
                    metricIcon
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        metricValue
                        metricLabel
                    }
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 4) {
                    metricIcon
                    metricValue
                    metricLabel
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center
        )
    }

    private var metricIcon: some View {
        Image(systemName: systemImage)
            .foregroundStyle(Ink.chartDim)
            .accessibilityHidden(true)
    }

    private var metricValue: some View {
        Text(value)
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Ink.chart)
            .multilineTextAlignment(
                dynamicTypeSize.isAccessibilitySize ? .leading : .center
            )
    }

    private var metricLabel: some View {
        Text(label)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(Ink.chartDim)
            .multilineTextAlignment(
                dynamicTypeSize.isAccessibilitySize ? .leading : .center
            )
    }
}
