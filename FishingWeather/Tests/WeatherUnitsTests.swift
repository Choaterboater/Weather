import Foundation
import Testing
@testable import BiteCast

@Suite("Weather units")
struct WeatherUnitsTests {
    @Test func roundsWholeDegrees() {
        let value = Measurement(value: 74.9, unit: UnitTemperature.fahrenheit)
        #expect(WeatherUnits.wholeTemperature(value, locale: Locale(identifier: "en_US")) == "75°")
    }

    @Test func convertsWithoutRounding() {
        let value = Measurement(value: 68, unit: UnitTemperature.fahrenheit)
        #expect(abs(WeatherUnits.value(value, unit: .celsius) - 20) < 0.001)
    }
}
