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

    static func value(
        _ measurement: Measurement<UnitTemperature>,
        unit: UnitTemperature
    ) -> Double {
        measurement.converted(to: unit).value
    }
}
