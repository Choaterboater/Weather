import CoreLocation
import Foundation
import Testing
@testable import BiteCast

@Suite("NWS provider")
struct NWSWeatherProviderTests {
    private let location = CLLocation(latitude: 30.2938, longitude: -86.0049)
    private let userAgent = "BiteCastTests/1.0 (app.choatelabs.bitecast.tests)"

    @Test func sendsRequiredHeadersOnEveryRequest() async throws {
        let recorder = NWSRequestRecorder(responses: NWSFixtures.minimumResponses)
        let provider = makeProvider(recorder: recorder)

        _ = try await provider.forecast(for: location)

        let requests = await recorder.requests
        #expect(requests.count == 6)
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "User-Agent") == userAgent
        })
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Accept") == "application/geo+json"
        })
        #expect(Set(requests.compactMap(NWSRequestRecorder.key)) == Set(NWSFixtures.minimumResponses.keys))
    }

    @Test func decodesCanonicalCurrentAndHourlyValues() async throws {
        let provider = makeProvider(
            recorder: NWSRequestRecorder(responses: NWSFixtures.minimumResponses)
        )

        let value = try await provider.forecast(for: location)

        #expect(value.coordinate == WeatherCoordinate(latitude: 30.2938, longitude: -86.0049))
        #expect(value.timeZoneIdentifier == "America/Chicago")
        #expect(value.provenance.source == .nws)
        #expect(value.provenance.isFallback == false)
        #expect(value.provenance.attribution == "National Weather Service")

        #expect(abs(value.current.temperatureCelsius - 28) < 0.001)
        #expect(abs(value.current.apparentTemperatureCelsius - 30) < 0.001)
        #expect(abs((value.current.dewPointCelsius ?? 0) - 21) < 0.001)
        #expect(abs((value.current.humidityFraction ?? 0) - 0.75) < 0.001)
        #expect(abs((value.current.pressureHPa ?? 0) - 1_019) < 0.001)
        #expect(abs((value.current.visibilityMeters ?? 0) - 16_093) < 0.001)
        #expect(value.current.conditionText == "Mostly Cloudy")
        #expect(value.current.symbolName == "cloud")
        #expect(abs(value.current.wind.directionDegrees - 225) < 0.001)
        #expect(abs(value.current.wind.speedMetersPerSecond - 5) < 0.001)
        #expect(value.current.wind.gustMetersPerSecond == nil)

        let first = try #require(value.hourly.first)
        #expect(abs(first.temperatureCelsius - 27.7778) < 0.001)
        #expect(abs((first.dewPointCelsius ?? 0) - 20) < 0.001)
        #expect(abs((first.humidityFraction ?? 0) - 0.70) < 0.001)
        #expect(abs((first.precipitationChance ?? 0) - 0.25) < 0.001)
        #expect(first.pressureHPa == nil)
        #expect(first.visibilityMeters == nil)
        #expect(first.precipitationMM == nil)
        #expect(first.symbolName == "cloud.bolt.rain")
        #expect(abs(first.wind.speedMetersPerSecond - (7.5 * 0.44704)) < 0.001)
    }

    @Test func usesUpperWindRangeForDailyPeak() async throws {
        let provider = makeProvider(
            recorder: NWSRequestRecorder(responses: NWSFixtures.minimumResponses)
        )

        let value = try await provider.forecast(for: location)

        let day = try #require(value.daily.first)
        #expect(abs(day.highCelsius - 30) < 0.001)
        #expect(abs(day.lowCelsius - 20) < 0.001)
        #expect(abs((day.precipitationChance ?? 0) - 0.40) < 0.001)
        #expect(day.conditionText == "Mostly Sunny")
        #expect(day.symbolName == "cloud.sun")
        #expect(abs((day.windMetersPerSecond ?? 0) - (17.5 * 0.44704)) < 0.001)
        #expect(abs((day.windPeakMetersPerSecond ?? 0) - (20 * 0.44704)) < 0.001)
    }

    @Test func dropsNightOnlyDailyGroupRatherThanInventingHigh() async throws {
        let provider = makeProvider(
            recorder: NWSRequestRecorder(responses: NWSFixtures.nightOnlyDaily)
        )

        let value = try await provider.forecast(for: location)

        #expect(value.daily.isEmpty)
    }

    @Test func dropsDayOnlyDailyGroupRatherThanInventingLow() async throws {
        let provider = makeProvider(
            recorder: NWSRequestRecorder(responses: NWSFixtures.dayOnlyDaily)
        )

        let value = try await provider.forecast(for: location)

        #expect(value.daily.isEmpty)
    }

    @Test func mapsAlertIdentityDatesAndDetails() async throws {
        let provider = makeProvider(
            recorder: NWSRequestRecorder(responses: NWSFixtures.minimumResponses)
        )

        let value = try await provider.forecast(for: location)

        let alert = try #require(value.alerts.first)
        #expect(alert.id == "urn:oid:123")
        #expect(alert.summary == "Severe Thunderstorm Warning issued July 12")
        #expect(alert.source == "NWS Tallahassee FL")
        #expect(alert.severity == "Severe")
        #expect(alert.startDate == NWSFixtures.date("2026-07-12T10:15:00-05:00"))
        #expect(alert.endDate == NWSFixtures.date("2026-07-12T12:00:00-05:00"))
        #expect(alert.detailsURL?.absoluteString == "https://api.weather.gov/alerts/urn:oid:123")
    }

    @Test func alertIdentityAndDetailsFallBackToTopLevelFeatureID() async throws {
        let provider = makeProvider(
            recorder: NWSRequestRecorder(responses: NWSFixtures.alertFeatureFallback)
        )

        let value = try await provider.forecast(for: location)

        let alert = try #require(value.alerts.first)
        #expect(alert.id == "https://api.weather.gov/alerts/feature-123")
        #expect(alert.detailsURL?.absoluteString == "https://api.weather.gov/alerts/feature-123")
    }

    @Test func usesInjectedAstronomyForTopLevelAndEveryDailyPoint() async throws {
        let recorder = NWSRequestRecorder(responses: NWSFixtures.minimumResponses)
        let provider = NWSWeatherProvider(
            loader: recorder.load,
            userAgent: userAgent,
            astronomy: { location, date, calendar in
                #expect(location.coordinate.latitude == 30.2938)
                #expect(location.coordinate.longitude == -86.0049)
                #expect(calendar.timeZone.identifier == "America/Chicago")
                return AstronomySnapshot(
                    sunrise: date,
                    sunset: nil,
                    moonrise: nil,
                    moonset: nil,
                    moonTransit: nil,
                    moonPhaseFraction: 0.25
                )
            }
        )

        let value = try await provider.forecast(for: location)

        #expect(value.astronomy.sunrise != nil)
        let day = try #require(value.daily.first)
        #expect(day.astronomy?.sunrise == day.date)
        #expect(day.astronomy?.moonPhaseFraction == 0.25)
    }

    @Test func absentObservationFallsBackToFirstHourWithoutPressure() async throws {
        let recorder = NWSRequestRecorder(responses: NWSFixtures.withoutObservation)
        let provider = makeProvider(recorder: recorder)

        let value = try await provider.forecast(for: location)

        #expect(abs(value.current.temperatureCelsius - 27.7778) < 0.001)
        #expect(abs(value.current.apparentTemperatureCelsius - 27.7778) < 0.001)
        #expect(value.current.conditionText == "Thunderstorms")
        #expect(value.current.pressureHPa == nil)
        #expect(value.current.wind.gustMetersPerSecond == nil)
        #expect(abs(value.current.wind.speedMetersPerSecond - (7.5 * 0.44704)) < 0.001)
    }

    @Test func missingObservationPressureRemainsNil() async throws {
        let recorder = NWSRequestRecorder(responses: NWSFixtures.withoutPressure)
        let provider = makeProvider(recorder: recorder)

        let value = try await provider.forecast(for: location)

        #expect(value.current.pressureHPa == nil)
    }

    @Test func omittedObservationDescriptionUsesHourlyCondition() async throws {
        let recorder = NWSRequestRecorder(responses: NWSFixtures.withoutObservationDescription)
        let provider = makeProvider(recorder: recorder)

        let value = try await provider.forecast(for: location)

        #expect(value.current.conditionText == "Thunderstorms")
    }

    @Test func omittedObservationUnitProducesNilMeasurement() async throws {
        let recorder = NWSRequestRecorder(responses: NWSFixtures.withoutPressureUnit)
        let provider = makeProvider(recorder: recorder)

        let value = try await provider.forecast(for: location)

        #expect(value.current.temperatureCelsius == 28)
        #expect(value.current.pressureHPa == nil)
    }

    @Test func unsupportedObservationUnitsUseAvailableFallbacks() async throws {
        let recorder = NWSRequestRecorder(responses: NWSFixtures.unsupportedObservationUnits)
        let provider = makeProvider(recorder: recorder)

        let value = try await provider.forecast(for: location)

        #expect(value.current.pressureHPa == nil)
        #expect(abs(value.current.wind.speedMetersPerSecond - (7.5 * 0.44704)) < 0.001)
    }

    @Test func latestObservation404UsesFirstHour() async throws {
        let recorder = NWSRequestRecorder(responses: NWSFixtures.latestObservationNotFound)
        let provider = makeProvider(recorder: recorder)

        let value = try await provider.forecast(for: location)

        #expect(abs(value.current.temperatureCelsius - 27.7778) < 0.001)
        #expect(value.current.pressureHPa == nil)
    }

    @Test func missingObservationIconPreservesNighttimeHourlySymbol() async throws {
        let recorder = NWSRequestRecorder(responses: NWSFixtures.withoutObservationIconAtNight)
        let provider = makeProvider(recorder: recorder)

        let value = try await provider.forecast(for: location)

        #expect(value.hourly.first?.symbolName == "moon.stars")
        #expect(value.current.symbolName == "moon.stars")
    }

    @Test func unsupportedForecastTemperatureUnitIsDecodingError() async {
        await expectDecoding(NWSFixtures.unsupportedHourlyTemperatureUnit)
    }

    @Test func unsupportedForecastWindUnitIsDecodingError() async {
        await expectDecoding(NWSFixtures.unsupportedHourlyWindUnit)
    }

    @Test func unsupportedForecastDirectionIsDecodingError() async {
        await expectDecoding(NWSFixtures.unsupportedHourlyDirection)
    }

    @Test func trimmedExactCalmWindIsAccepted() async throws {
        let recorder = NWSRequestRecorder(responses: NWSFixtures.hourlyWind("  Calm  "))
        let provider = makeProvider(recorder: recorder)

        let value = try await provider.forecast(for: location)

        #expect(value.hourly.first?.wind.speedMetersPerSecond == 0)
    }

    @Test func malformedCalmWindIsDecodingError() async {
        await expectDecoding(NWSFixtures.hourlyWind("calm furlongs"))
    }

    @Test func embeddedMPHGarbageIsDecodingError() async {
        await expectDecoding(NWSFixtures.hourlyWind("gusts 5 to 10 mph later"))
    }

    @Test func unsupportedPointMaps404() async {
        let recorder = NWSRequestRecorder(responses: [
            NWSFixtures.pointKey: .status(404),
        ])
        let provider = makeProvider(recorder: recorder)

        await #expect(throws: WeatherProviderError.unsupportedRegion) {
            _ = try await provider.forecast(for: location)
        }
    }

    @Test func rateLimitIncludesRetryAfter() async {
        let recorder = NWSRequestRecorder(responses: [
            NWSFixtures.pointKey: .status(429, headers: ["Retry-After": "120"]),
        ])
        let provider = makeProvider(recorder: recorder)

        await #expect(throws: WeatherProviderError.rateLimited(retryAfter: 120)) {
            _ = try await provider.forecast(for: location)
        }
    }

    @Test func negativeRetryAfterClampsToZero() async {
        let recorder = NWSRequestRecorder(responses: [
            NWSFixtures.pointKey: .status(429, headers: ["Retry-After": "-5"]),
        ])
        let provider = makeProvider(recorder: recorder)

        await #expect(throws: WeatherProviderError.rateLimited(retryAfter: 0)) {
            _ = try await provider.forecast(for: location)
        }
    }

    @Test func serverFailureMapsServiceUnavailable() async {
        let recorder = NWSRequestRecorder(responses: [
            NWSFixtures.pointKey: .status(503),
        ])
        let provider = makeProvider(recorder: recorder)

        await #expect(throws: WeatherProviderError.serviceUnavailable) {
            _ = try await provider.forecast(for: location)
        }
    }

    @Test func malformedJSONMapsDecodingError() async {
        let recorder = NWSRequestRecorder(responses: [
            NWSFixtures.pointKey: .json(#"{"properties": "#),
        ])
        let provider = makeProvider(recorder: recorder)

        do {
            _ = try await provider.forecast(for: location)
            Issue.record("Expected a decoding error")
        } catch let error as WeatherProviderError {
            guard case let .decoding(message) = error else {
                Issue.record("Expected decoding, got \(error)")
                return
            }
            #expect(message?.isEmpty == false)
        } catch {
            Issue.record("Expected WeatherProviderError, got \(error)")
        }
    }

    @Test func laterChildFailureCancelsEarlierSuspendedRequest() async {
        let gate = NWSFailFastGate()
        let loader = NWSFailFastLoader(gate: gate)
        let provider = NWSWeatherProvider(
            loader: loader.load,
            userAgent: userAgent
        )

        await #expect(throws: WeatherProviderError.serviceUnavailable) {
            _ = try await provider.forecast(for: location)
        }
        let cancellationObserved = await gate.waitUntilCancellation()
        #expect(cancellationObserved)
    }

    @Test func preservesDirectCancellation() async {
        let provider = NWSWeatherProvider(
            loader: { _ in throw CancellationError() },
            userAgent: userAgent
        )

        await #expect(throws: CancellationError.self) {
            _ = try await provider.forecast(for: location)
        }
    }

    @Test func preservesURLCancellation() async {
        let provider = NWSWeatherProvider(
            loader: { _ in throw URLError(.cancelled) },
            userAgent: userAgent
        )

        do {
            _ = try await provider.forecast(for: location)
            Issue.record("Expected URL cancellation")
        } catch let error as URLError {
            #expect(error.code == .cancelled)
        } catch {
            Issue.record("Expected URLError.cancelled, got \(error)")
        }
    }

    private func makeProvider(recorder: NWSRequestRecorder) -> NWSWeatherProvider {
        NWSWeatherProvider(
            loader: recorder.load,
            userAgent: userAgent,
            astronomy: { _, _, _ in .empty }
        )
    }

    private func expectDecoding(_ responses: [String: NWSRequestRecorder.Response]) async {
        let provider = makeProvider(recorder: NWSRequestRecorder(responses: responses))

        do {
            _ = try await provider.forecast(for: location)
            Issue.record("Expected a decoding error")
        } catch let error as WeatherProviderError {
            guard case .decoding = error else {
                Issue.record("Expected decoding, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected WeatherProviderError, got \(error)")
        }
    }
}

private struct NWSFailFastGate: Sendable {
    private let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private let hold: AsyncStream<Void>
    private let holdContinuation: AsyncStream<Void>.Continuation
    private let cancellation: AsyncStream<Void>
    private let cancellationContinuation: AsyncStream<Void>.Continuation

    init() {
        let started = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.started = started.stream
        startedContinuation = started.continuation

        let hold = AsyncStream.makeStream(of: Void.self)
        self.hold = hold.stream
        holdContinuation = hold.continuation

        let cancellation = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.cancellation = cancellation.stream
        cancellationContinuation = cancellation.continuation
    }

    func suspendUntilCancelled() async throws {
        try await withTaskCancellationHandler {
            startedContinuation.yield()
            startedContinuation.finish()
            for await _ in hold {}
            try Task.checkCancellation()
        } onCancel: {
            cancellationContinuation.yield()
            cancellationContinuation.finish()
            holdContinuation.finish()
        }
    }

    func waitUntilStarted() async {
        for await _ in started { return }
    }

    func waitUntilCancellation() async -> Bool {
        for await _ in cancellation { return true }
        return false
    }
}

private struct NWSFailFastLoader: Sendable {
    let gate: NWSFailFastGate

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard let key = NWSRequestRecorder.key(request) else {
            throw URLError(.badURL)
        }

        if key == "/gridpoints/TAE/50,50/forecast/hourly" {
            try await gate.suspendUntilCancelled()
            throw URLError(.cancelled)
        }

        let response: NWSRequestRecorder.Response
        if key == "/gridpoints/TAE/50,50/forecast" {
            await gate.waitUntilStarted()
            response = .status(503)
        } else if let fixture = NWSFixtures.minimumResponses[key] {
            response = fixture
        } else {
            throw URLError(.resourceUnavailable)
        }

        guard let httpResponse = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.weather.gov")!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        ) else {
            throw URLError(.badServerResponse)
        }
        return (response.data, httpResponse)
    }
}

private actor NWSRequestRecorder {
    struct Response: Sendable {
        let data: Data
        let statusCode: Int
        let headers: [String: String]

        static func json(
            _ json: String,
            statusCode: Int = 200,
            headers: [String: String] = [:]
        ) -> Self {
            Self(data: Data(json.utf8), statusCode: statusCode, headers: headers)
        }

        static func status(_ statusCode: Int, headers: [String: String] = [:]) -> Self {
            Self(data: Data(), statusCode: statusCode, headers: headers)
        }
    }

    private let responses: [String: Response]
    private(set) var requests: [URLRequest] = []

    init(responses: [String: Response]) {
        self.responses = responses
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard let key = Self.key(request), let stub = responses[key] else {
            throw URLError(.resourceUnavailable)
        }
        let response = try #require(HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.weather.gov")!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        ))
        return (stub.data, response)
    }

    nonisolated static func key(_ request: URLRequest) -> String? {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        if components.path == "/alerts/active" {
            let point = components.queryItems?.first(where: { $0.name == "point" })?.value
            return point.map { "\(components.path)?point=\($0)" }
        }
        return components.path
    }
}

private enum NWSFixtures {
    typealias Response = NWSRequestRecorder.Response

    static let pointKey = "/points/30.2938,-86.0049"

    static var minimumResponses: [String: Response] {
        [
            pointKey: .json(point),
            "/gridpoints/TAE/50,50/forecast/hourly": .json(hourly),
            "/gridpoints/TAE/50,50/forecast": .json(daily),
            "/gridpoints/TAE/50,50/stations": .json(stations),
            "/stations/KPAM/observations/latest": .json(observation),
            "/alerts/active?point=30.2938,-86.0049": .json(alerts),
        ]
    }

    static var withoutObservation: [String: Response] {
        var responses = minimumResponses
        responses["/gridpoints/TAE/50,50/stations"] = .json(emptyStations)
        responses.removeValue(forKey: "/stations/KPAM/observations/latest")
        return responses
    }

    static var nightOnlyDaily: [String: Response] {
        var responses = minimumResponses
        responses["/gridpoints/TAE/50,50/forecast"] = .json(dailyResponse(nightPeriod))
        return responses
    }

    static var dayOnlyDaily: [String: Response] {
        var responses = minimumResponses
        responses["/gridpoints/TAE/50,50/forecast"] = .json(dailyResponse(dayPeriod))
        return responses
    }

    static var alertFeatureFallback: [String: Response] {
        var responses = minimumResponses
        responses["/alerts/active?point=30.2938,-86.0049"] = .json(
            alerts
                .replacingOccurrences(
                    of: #""id": "urn:oid:123","#,
                    with: #""id": "","#
                )
                .replacingOccurrences(
                    of: #""@id": "https://api.weather.gov/alerts/urn:oid:123""#,
                    with: #""@id": "not-a-url""#
                )
        )
        return responses
    }

    static var withoutPressure: [String: Response] {
        var responses = minimumResponses
        responses["/stations/KPAM/observations/latest"] = .json(
            observation.replacingOccurrences(
                of: #""barometricPressure":{"unitCode":"wmoUnit:Pa","value":101900},"#,
                with: ""
            )
        )
        return responses
    }

    static var withoutPressureUnit: [String: Response] {
        var responses = minimumResponses
        responses["/stations/KPAM/observations/latest"] = .json(
            observation.replacingOccurrences(
                of: #""barometricPressure":{"unitCode":"wmoUnit:Pa","value":101900}"#,
                with: #""barometricPressure":{"value":101900}"#
            )
        )
        return responses
    }

    static var withoutObservationDescription: [String: Response] {
        var responses = minimumResponses
        responses["/stations/KPAM/observations/latest"] = .json(
            observation.replacingOccurrences(
                of: #""textDescription": "Mostly Cloudy","#,
                with: ""
            )
        )
        return responses
    }

    static var unsupportedObservationUnits: [String: Response] {
        var responses = minimumResponses
        responses["/stations/KPAM/observations/latest"] = .json(
            observation
                .replacingOccurrences(
                    of: #""windSpeed": {"unitCode": "wmoUnit:km_h-1", "value": 18}"#,
                    with: #""windSpeed": {"unitCode": "wmoUnit:unknown", "value": 18}"#
                )
                .replacingOccurrences(
                    of: #""barometricPressure":{"unitCode":"wmoUnit:Pa","value":101900}"#,
                    with: #""barometricPressure":{"unitCode":"wmoUnit:unknown","value":101900}"#
                )
        )
        return responses
    }

    static var latestObservationNotFound: [String: Response] {
        var responses = minimumResponses
        responses["/stations/KPAM/observations/latest"] = .status(404)
        return responses
    }

    static var withoutObservationIconAtNight: [String: Response] {
        var responses = minimumResponses
        responses["/gridpoints/TAE/50,50/forecast/hourly"] = .json(
            hourly
                .replacingOccurrences(
                    of: "https://api.weather.gov/icons/land/day/tsra_hi,40?size=medium",
                    with: "https://api.weather.gov/icons/land/night/skc?size=medium"
                )
                .replacingOccurrences(
                    of: #""shortForecast": "Thunderstorms""#,
                    with: #""shortForecast": "Clear""#
                )
        )
        responses["/stations/KPAM/observations/latest"] = .json(
            observation
                .replacingOccurrences(
                    of: #""textDescription": "Mostly Cloudy""#,
                    with: #""textDescription": "Clear""#
                )
                .replacingOccurrences(
                    of: #""icon": "https://api.weather.gov/icons/land/day/bkn?size=medium","#,
                    with: ""
                )
        )
        return responses
    }

    static var unsupportedHourlyTemperatureUnit: [String: Response] {
        replacingHourly(#""temperatureUnit": "F""#, with: #""temperatureUnit": "unknown""#)
    }

    static var unsupportedHourlyWindUnit: [String: Response] {
        replacingHourly(#""windSpeed": "5 to 10 mph""#, with: #""windSpeed": "5 to 10 furlongs""#)
    }

    static var unsupportedHourlyDirection: [String: Response] {
        replacingHourly(#""windDirection": "SW""#, with: #""windDirection": "VARIABLE""#)
    }

    static func hourlyWind(_ value: String) -> [String: Response] {
        replacingHourly(
            #""windSpeed": "5 to 10 mph""#,
            with: "\"windSpeed\": \"\(value)\""
        )
    }

    private static func replacingHourly(_ target: String, with replacement: String) -> [String: Response] {
        var responses = minimumResponses
        responses["/gridpoints/TAE/50,50/forecast/hourly"] = .json(
            hourly.replacingOccurrences(of: target, with: replacement)
        )
        return responses
    }

    static func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static let point = #"""
    {
      "properties": {
        "forecast": "https://api.weather.gov/gridpoints/TAE/50,50/forecast",
        "forecastHourly": "https://api.weather.gov/gridpoints/TAE/50,50/forecast/hourly",
        "observationStations": "https://api.weather.gov/gridpoints/TAE/50,50/stations",
        "timeZone": "America/Chicago"
      }
    }
    """#

    private static let hourly = #"""
    {
      "properties": {
        "periods": [
          {
            "startTime": "2026-07-12T12:00:00-05:00",
            "temperature": 82,
            "temperatureUnit": "F",
            "probabilityOfPrecipitation": {"unitCode": "wmoUnit:percent", "value": 25},
            "dewpoint": {"unitCode": "wmoUnit:degC", "value": 20},
            "relativeHumidity": {"unitCode": "wmoUnit:percent", "value": 70},
            "windSpeed": "5 to 10 mph",
            "windDirection": "SW",
            "icon": "https://api.weather.gov/icons/land/day/tsra_hi,40?size=medium",
            "shortForecast": "Thunderstorms"
          },
          {
            "startTime": "2026-07-12T13:00:00-05:00",
            "temperature": 83,
            "temperatureUnit": "F",
            "probabilityOfPrecipitation": {"unitCode": "wmoUnit:percent", "value": null},
            "dewpoint": {"unitCode": "wmoUnit:degC", "value": null},
            "relativeHumidity": {"unitCode": "wmoUnit:percent", "value": null},
            "windSpeed": "10 mph",
            "windDirection": "S",
            "icon": "https://api.weather.gov/icons/land/day/skc?size=medium",
            "shortForecast": "Sunny"
          }
        ]
      }
    }
    """#

    private static let daily = dailyResponse("\(dayPeriod),\(nightPeriod)")

    private static func dailyResponse(_ periods: String) -> String {
        """
        {
          "properties": {
            "periods": [\(periods)]
          }
        }
        """
    }

    private static let dayPeriod = #"""
    {
      "startTime": "2026-07-12T06:00:00-05:00",
      "isDaytime": true,
      "temperature": 86,
      "temperatureUnit": "F",
      "probabilityOfPrecipitation": {"unitCode": "wmoUnit:percent", "value": 20},
      "windSpeed": "10 to 15 mph",
      "windDirection": "S",
      "icon": "https://api.weather.gov/icons/land/day/sct?size=medium",
      "shortForecast": "Mostly Sunny"
    }
    """#

    private static let nightPeriod = #"""
    {
      "startTime": "2026-07-12T18:00:00-05:00",
      "isDaytime": false,
      "temperature": 68,
      "temperatureUnit": "F",
      "probabilityOfPrecipitation": {"unitCode": "wmoUnit:percent", "value": 40},
      "windSpeed": "15 to 20 mph",
      "windDirection": "SW",
      "icon": "https://api.weather.gov/icons/land/night/tsra,40?size=medium",
      "shortForecast": "Chance Thunderstorms"
    }
    """#

    private static let stations = #"""
    {
      "features": [
        {"id": "https://api.weather.gov/stations/KPAM"}
      ]
    }
    """#

    private static let emptyStations = #"""
    {"features": []}
    """#

    private static let observation = #"""
    {
      "properties": {
        "timestamp": "2026-07-12T11:53:00-05:00",
        "textDescription": "Mostly Cloudy",
        "icon": "https://api.weather.gov/icons/land/day/bkn?size=medium",
        "temperature": {"unitCode": "wmoUnit:degC", "value": 28},
        "dewpoint": {"unitCode": "wmoUnit:degC", "value": 21},
        "windChill": {"unitCode": "wmoUnit:degC", "value": null},
        "heatIndex": {"unitCode": "wmoUnit:degC", "value": 30},
        "windDirection": {"unitCode": "wmoUnit:degree_(angle)", "value": 225},
        "windSpeed": {"unitCode": "wmoUnit:km_h-1", "value": 18},
        "windGust": {"unitCode": "wmoUnit:km_h-1", "value": null},
        "barometricPressure":{"unitCode":"wmoUnit:Pa","value":101900},
        "visibility": {"unitCode": "wmoUnit:m", "value": 16093},
        "relativeHumidity": {"unitCode": "wmoUnit:percent", "value": 75}
      }
    }
    """#

    private static let alerts = #"""
    {
      "features": [
        {
          "id": "https://api.weather.gov/alerts/feature-123",
          "properties": {
            "id": "urn:oid:123",
            "@id": "https://api.weather.gov/alerts/urn:oid:123",
            "event": "Severe Thunderstorm Warning",
            "headline": "Severe Thunderstorm Warning issued July 12",
            "senderName": "NWS Tallahassee FL",
            "severity": "Severe",
            "effective": "2026-07-12T10:00:00-05:00",
            "onset": "2026-07-12T10:15:00-05:00",
            "ends": "2026-07-12T12:00:00-05:00",
            "expires": "2026-07-12T12:15:00-05:00"
          }
        }
      ]
    }
    """#
}
