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

    @Test func formatsCanonicalCelsiusAtWholeDegrees() {
        #expect(WeatherUnits.wholeTemperature(
            celsius: 23.2778,
            locale: Locale(identifier: "en_US")
        ) == "74°")
    }

    @Test func convertsCanonicalWindAndCompassDirection() {
        #expect(abs(WeatherUnits.milesPerHour(metersPerSecond: 10) - 22.3694) < 0.001)
        #expect(WeatherUnits.compassAbbreviation(degrees: 0) == "N")
        #expect(WeatherUnits.compassAbbreviation(degrees: 225) == "SW")
        #expect(WeatherUnits.compassAbbreviation(degrees: -45) == "NW")
    }

    @Test func chartSamplesPreserveCanonicalCelsius() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let point = HourlyWeatherPoint(
            date: date,
            temperatureCelsius: 20,
            apparentTemperatureCelsius: nil,
            dewPointCelsius: nil,
            humidityFraction: nil,
            pressureHPa: nil,
            visibilityMeters: nil,
            uvIndex: nil,
            cloudCoverFraction: nil,
            precipitationChance: nil,
            precipitationMM: nil,
            conditionText: "Clear",
            symbolName: "sun.max",
            wind: WindSnapshot(
                directionDegrees: 180,
                speedMetersPerSecond: 2,
                gustMetersPerSecond: nil
            )
        )

        let sample = try #require(
            [point].samples(now: date.addingTimeInterval(-1)).first
        )

        #expect(sample.temperatureCelsius == 20)
    }
}
