import CoreLocation
import Foundation
import Testing
import WeatherKit
@testable import BiteCast

@Suite("WeatherKit adapter")
struct WeatherKitAdapterTests {
    @Test func canonicalWind() {
        let wind = WeatherKitAdapter.wind(
            directionDegrees: 225,
            speedMetersPerSecond: 5,
            gustMetersPerSecond: 8
        )

        #expect(wind.directionDegrees == 225)
        #expect(wind.speedMetersPerSecond == 5)
        #expect(wind.gustMetersPerSecond == 8)
    }

    @Test func clampsFractions() {
        #expect(WeatherKitAdapter.fraction(1.4) == 1)
        #expect(WeatherKitAdapter.fraction(-0.1) == 0)
        #expect(WeatherKitAdapter.fraction(0.4) == 0.4)
    }

    @Test func convertsCanonicalMeasurements() {
        let temperature = Measurement(value: 68, unit: UnitTemperature.fahrenheit)
        let distance = Measurement(value: 1, unit: UnitLength.kilometers)
        let speed = Measurement(value: 36, unit: UnitSpeed.kilometersPerHour)
        let pressure = Measurement(value: 1, unit: UnitPressure.bars)
        let precipitation = Measurement(value: 1, unit: UnitLength.centimeters)

        #expect(abs(WeatherKitAdapter.celsius(temperature) - 20) < 0.001)
        #expect(abs(WeatherKitAdapter.meters(distance) - 1_000) < 0.001)
        #expect(abs(WeatherKitAdapter.metersPerSecond(speed) - 10) < 0.001)
        #expect(abs(WeatherKitAdapter.hectopascals(pressure) - 1_000) < 0.001)
        #expect(abs(WeatherKitAdapter.millimeters(precipitation) - 10) < 0.001)
    }

    @Test func requestsSixHoursBackThroughFortyEightHoursAhead() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let window = WeatherKitAdapter.requestWindow(now: now)

        #expect(window.start == now.addingTimeInterval(-6 * 3_600))
        #expect(window.end == now.addingTimeInterval(48 * 3_600))
    }

    @Test func mapsEveryWeatherKitMoonPhaseToCategoryAnchor() {
        let expected: [MoonPhase: Double] = [
            .new: 0,
            .waxingCrescent: 0.125,
            .firstQuarter: 0.25,
            .waxingGibbous: 0.375,
            .full: 0.5,
            .waningGibbous: 0.625,
            .lastQuarter: 0.75,
            .waningCrescent: 0.875,
        ]

        #expect(Set(expected.keys) == Set(MoonPhase.allCases))
        for phase in MoonPhase.allCases {
            #expect(WeatherKitAdapter.moonPhaseFraction(phase) == expected[phase])
        }
    }

    @Test func classifiesWeatherKitAuthenticationFailures() {
        #expect(WeatherKitAdapter.providerError(WeatherError.permissionDenied) == .authentication)

        let listenerFailure = NSError(
            domain: "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "JWT listener failed"]
        )
        #expect(WeatherKitAdapter.providerError(listenerFailure) == .authentication)
    }

    @Test func classifiesURLFailuresAsNetworkErrors() {
        let failure = URLError(.notConnectedToInternet)

        guard case let .network(message) = WeatherKitAdapter.providerError(failure) else {
            Issue.record("Expected a network error")
            return
        }
        #expect(message?.isEmpty == false)
    }

    @Test func providerPreservesCancellation() async {
        let provider = WeatherKitProvider(worker: { _, _, _ in
            throw CancellationError()
        })

        await #expect(throws: CancellationError.self) {
            _ = try await provider.forecast(
                for: CLLocation(latitude: 30.29, longitude: -86)
            )
        }
    }
}
