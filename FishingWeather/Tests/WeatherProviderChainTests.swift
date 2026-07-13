import CoreLocation
import Foundation
import Testing
@testable import BiteCast

@Suite("Weather provider chain")
struct WeatherProviderChainTests {
    @Test func fallsThroughAndMarksFallback() async throws {
        let primary = StubProvider(result: .failure(WeatherProviderError.authentication))
        let fallback = StubProvider(result: .success(.fixture(source: .nws)))

        let result = try await WeatherProviderChain(providers: [primary, fallback])
            .forecast(for: CLLocation(latitude: 30.29, longitude: -86.00))

        #expect(result.provenance == WeatherProvenance(
            source: .nws,
            fetchedAt: .fixture,
            isFallback: true,
            attribution: "National Weather Service"
        ))
    }

    @Test func primarySuccessRemainsNonFallback() async throws {
        let primary = StubProvider(result: .success(.fixture(source: .weatherKit)))

        let result = try await WeatherProviderChain(providers: [primary])
            .forecast(for: CLLocation(latitude: 30.29, longitude: -86.00))

        #expect(!result.provenance.isFallback)
    }

    @Test func alreadyMarkedFallbackRemainsFallback() async throws {
        let primary = StubProvider(
            result: .success(.fixture(source: .cache, isFallback: true))
        )

        let result = try await WeatherProviderChain(providers: [primary])
            .forecast(for: CLLocation(latitude: 30.29, longitude: -86.00))

        #expect(result.provenance.isFallback)
    }

    @Test func cancellationDoesNotFallThrough() async {
        let canceled = StubProvider(result: .failure(CancellationError()))
        let fallback = StubProvider(result: .success(.fixture(source: .nws)))

        await #expect(throws: CancellationError.self) {
            _ = try await WeatherProviderChain(providers: [canceled, fallback])
                .forecast(for: CLLocation(latitude: 30.29, longitude: -86.00))
        }
    }

    @Test func urlCancellationDoesNotFallThrough() async {
        let canceled = StubProvider(result: .failure(URLError(.cancelled)))
        let fallback = StubProvider(result: .success(.fixture(source: .nws)))

        do {
            _ = try await WeatherProviderChain(providers: [canceled, fallback])
                .forecast(for: CLLocation(latitude: 30.29, longitude: -86.00))
            Issue.record("Expected URL cancellation")
        } catch let error as URLError {
            #expect(error.code == .cancelled)
        } catch {
            Issue.record("Expected URLError.cancelled, got \(error)")
        }
    }

    @Test func aggregatesFailuresInAttemptOrder() async {
        let typedFailure = StubProvider(result: .failure(WeatherProviderError.authentication))
        let genericFailure = StubProvider(result: .failure(FixtureError.offline))
        let expected = WeatherProviderError.allProvidersFailed([
            WeatherProviderFailure(provider: "StubProvider", error: .authentication),
            WeatherProviderFailure(provider: "StubProvider", error: .network("offline")),
        ])

        do {
            _ = try await WeatherProviderChain(providers: [typedFailure, genericFailure])
                .forecast(for: CLLocation(latitude: 30.29, longitude: -86.00))
            Issue.record("Expected the provider chain to fail")
        } catch let error as WeatherProviderError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected WeatherProviderError, got \(error)")
        }
    }

    @Test func emptyChainReportsEmptyAggregateFailure() async {
        await #expect(throws: WeatherProviderError.allProvidersFailed([])) {
            _ = try await WeatherProviderChain(providers: [])
                .forecast(for: CLLocation(latitude: 30.29, longitude: -86.00))
        }
    }

    @Test func snapshotRoundTripsThroughCodable() throws {
        let snapshot = WeatherSnapshot.fixture(source: .weatherKit)

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: encoded)

        #expect(decoded == snapshot)
        #expect(decoded.daily.first?.astronomy == snapshot.astronomy)
        #expect(decoded.daily.first?.windMetersPerSecond == 5)
        #expect(decoded.daily.first?.windPeakMetersPerSecond == 8)
    }
}

private struct StubProvider: WeatherProvider {
    let result: Result<WeatherSnapshot, any Error>

    func forecast(for location: CLLocation) async throws -> WeatherSnapshot {
        try result.get()
    }
}

private enum FixtureError: Error {
    case offline
}

private extension Date {
    static let fixture = Date(timeIntervalSince1970: 1_800_000_000)
}

private extension WeatherSnapshot {
    static func fixture(
        source: WeatherSource,
        isFallback: Bool = false
    ) -> WeatherSnapshot {
        let wind = WindSnapshot(
            directionDegrees: 225,
            speedMetersPerSecond: 4.5,
            gustMetersPerSecond: 7
        )
        let current = CurrentConditionsSnapshot(
            date: .fixture,
            temperatureCelsius: 25,
            apparentTemperatureCelsius: 26,
            dewPointCelsius: 20,
            humidityFraction: 0.72,
            pressureHPa: 1_019,
            visibilityMeters: 16_000,
            uvIndex: 5,
            conditionText: "Partly Cloudy",
            symbolName: "cloud.sun",
            wind: wind
        )
        let hourly = HourlyWeatherPoint(
            date: .fixture,
            temperatureCelsius: 25,
            apparentTemperatureCelsius: 26,
            dewPointCelsius: 20,
            humidityFraction: 0.72,
            pressureHPa: 1_019,
            visibilityMeters: 16_000,
            uvIndex: 5,
            cloudCoverFraction: 0.35,
            precipitationChance: 0.15,
            precipitationMM: 0,
            conditionText: "Partly Cloudy",
            symbolName: "cloud.sun",
            wind: wind
        )
        let daily = DailyWeatherPoint(
            date: .fixture,
            lowCelsius: 22,
            highCelsius: 29,
            precipitationChance: 0.2,
            conditionText: "Partly Cloudy",
            symbolName: "cloud.sun",
            windMetersPerSecond: 5,
            windPeakMetersPerSecond: 8,
            astronomy: AstronomySnapshot(
                sunrise: .fixture.addingTimeInterval(-6 * 3_600),
                sunset: .fixture.addingTimeInterval(6 * 3_600),
                moonrise: .fixture.addingTimeInterval(-3 * 3_600),
                moonset: .fixture.addingTimeInterval(9 * 3_600),
                moonTransit: .fixture.addingTimeInterval(3 * 3_600),
                moonPhaseFraction: 0.25
            )
        )
        let alert = WeatherAlertSnapshot(
            id: "alert-1",
            summary: "Small Craft Advisory",
            source: "National Weather Service",
            severity: "Moderate",
            startDate: .fixture,
            endDate: .fixture.addingTimeInterval(3_600),
            detailsURL: URL(string: "https://example.com/alert-1")
        )

        return WeatherSnapshot(
            coordinate: WeatherCoordinate(latitude: 30.29, longitude: -86.00),
            timeZoneIdentifier: "America/Chicago",
            current: current,
            hourly: [hourly],
            daily: [daily],
            alerts: [alert],
            astronomy: AstronomySnapshot(
                sunrise: .fixture.addingTimeInterval(-6 * 3_600),
                sunset: .fixture.addingTimeInterval(6 * 3_600),
                moonrise: .fixture.addingTimeInterval(-3 * 3_600),
                moonset: .fixture.addingTimeInterval(9 * 3_600),
                moonTransit: .fixture.addingTimeInterval(3 * 3_600),
                moonPhaseFraction: 0.25
            ),
            provenance: WeatherProvenance(
                source: source,
                fetchedAt: .fixture,
                isFallback: isFallback,
                attribution: source == .nws ? "National Weather Service" : nil
            )
        )
    }
}
