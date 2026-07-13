import Foundation

enum WeatherUnits {
    static func wholeTemperature(
        _ value: Measurement<UnitTemperature>,
        locale: Locale = .current
    ) -> String {
        value.formatted(
            .measurement(
                width: .narrow,
                usage: .weather,
                numberFormatStyle: .number.precision(.fractionLength(0))
            ).locale(locale)
        )
    }

    static func wholeTemperature(
        celsius: Double,
        locale: Locale = .current
    ) -> String {
        wholeTemperature(
            Measurement(value: celsius, unit: UnitTemperature.celsius),
            locale: locale
        )
    }

    static func milesPerHour(metersPerSecond: Double) -> Double {
        Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond)
            .converted(to: .milesPerHour)
            .value
    }

    static func compassAbbreviation(degrees: Double) -> String {
        guard degrees.isFinite else { return "—" }
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = degrees.truncatingRemainder(dividingBy: 360) + 360
        let index = Int(((normalized.truncatingRemainder(dividingBy: 360)) + 22.5) / 45) % names.count
        return names[index]
    }

    static func value(
        _ measurement: Measurement<UnitTemperature>,
        unit: UnitTemperature
    ) -> Double {
        measurement.converted(to: unit).value
    }
}
