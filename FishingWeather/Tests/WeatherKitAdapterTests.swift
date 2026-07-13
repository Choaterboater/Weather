import CoreLocation
import Foundation
import Testing
import WeatherKit
@testable import BiteCast

@Suite("WeatherKit adapter")
struct WeatherKitAdapterTests {
    private let legalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
    private let lightMarkURL = URL(string: "https://weatherkit.apple.com/assets/branding/en/Apple_Weather_wht_en_3X_090122.png")!
    private let darkMarkURL = URL(string: "https://weatherkit.apple.com/assets/branding/en/Apple_Weather_blk_en_3X_090122.png")!

    @Test("WeatherKit attribution maps every required provider field")
    func mapsRequiredAttribution() throws {
        let value = try #require(WeatherKitAdapter.attribution(
            serviceName: "Apple Weather",
            legalPageURL: legalURL,
            combinedMarkLightURL: lightMarkURL,
            combinedMarkDarkURL: darkMarkURL,
            legalText: "Weather data sources and legal attribution"
        ))

        #expect(value.providerKind == .appleWeather)
        #expect(value.serviceName == "Apple Weather")
        #expect(value.legalPageURL == legalURL)
        #expect(value.combinedMarkLightURL == lightMarkURL)
        #expect(value.combinedMarkDarkURL == darkMarkURL)
        #expect(value.legalText == "Weather data sources and legal attribution")
    }

    @Test("WeatherKit attribution rejects insecure provider destinations")
    func rejectsInsecureAttributionURLs() {
        let insecureLegal = WeatherKitAdapter.attribution(
            serviceName: "Apple Weather",
            legalPageURL: URL(string: "http://weatherkit.apple.com/legal-attribution.html")!,
            combinedMarkLightURL: lightMarkURL,
            combinedMarkDarkURL: darkMarkURL,
            legalText: "Weather data sources and legal attribution"
        )
        let insecureMark = WeatherKitAdapter.attribution(
            serviceName: "Apple Weather",
            legalPageURL: legalURL,
            combinedMarkLightURL: URL(string: "http://weatherkit.apple.com/light.png")!,
            combinedMarkDarkURL: darkMarkURL,
            legalText: "Weather data sources and legal attribution"
        )

        #expect(insecureLegal == nil)
        #expect(insecureMark == nil)
    }

    @Test("WeatherKit attribution rejects non-canonical HTTPS URLs")
    func rejectsNonCanonicalAttributionURLs() {
        let unsafeURLs = [
            URL(string: "https://user:secret@weatherkit.apple.com/legal")!,
            URL(string: "https://weatherkit.apple.com:443/legal")!,
            URL(string: "https://weatherkit.apple.com/legal?redirect=1")!,
            URL(string: "https://weatherkit.apple.com/legal#fragment")!,
        ]

        for unsafeURL in unsafeURLs {
            #expect(WeatherKitAdapter.attribution(
                serviceName: "Apple Weather",
                legalPageURL: unsafeURL,
                combinedMarkLightURL: lightMarkURL,
                combinedMarkDarkURL: darkMarkURL,
                legalText: "Weather data sources and legal attribution"
            ) == nil)
        }
    }

    @Test("Missing required WeatherKit attribution fails before weather can be displayed")
    func missingRequiredAttributionFailsProvider() async {
        let provider = WeatherKitProvider(
            worker: { _, _, _ in
                Issue.record("Weather payload must not be displayed without required attribution")
                throw WeatherKitFixtureError.unknown
            },
            attributionWorker: { nil }
        )

        await #expect(throws: WeatherProviderError.decoding("WeatherKit attribution was unavailable")) {
            _ = try await provider.forecast(
                for: CLLocation(latitude: 30.29, longitude: -86)
            )
        }
    }

    @Test("Apple expiry uses the earliest metadata date and never exceeds one hour")
    func selectsEarliestFiniteExpiryWithCap() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(WeatherKitAdapter.expirationDate(
            fetchedAt: fetchedAt,
            providerExpirations: [
                fetchedAt.addingTimeInterval(3_600),
                fetchedAt.addingTimeInterval(1_200),
                fetchedAt.addingTimeInterval(7_200),
            ]
        ) == fetchedAt.addingTimeInterval(1_200))
        #expect(WeatherKitAdapter.expirationDate(
            fetchedAt: fetchedAt,
            providerExpirations: [fetchedAt.addingTimeInterval(7_200)]
        ) == fetchedAt.addingTimeInterval(3_600))
        #expect(WeatherKitAdapter.expirationDate(
            fetchedAt: fetchedAt,
            providerExpirations: [fetchedAt]
        ) == nil)
    }

    @Test("Combined-mark requests use app identity and hydrate both provider images")
    func combinedMarksUseIdentifiedRequests() async throws {
        let recorder = WeatherMarkRequestRecorder(data: Self.validPNG)
        let loader = WeatherAttributionMarkLoader(loader: recorder.load)

        let value = try await loader.hydrate(Self.validAttribution)
        let requests = await recorder.requests

        #expect(requests.count == 2)
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "User-Agent") == AppIdentity.userAgent
        })
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Accept") == "image/*"
        })
        #expect(value.combinedMarkLightData == Self.validPNG)
        #expect(value.combinedMarkDarkData == Self.validPNG)
        #expect(WeatherAttributionMarkLoader.hasUsableAppleMarks(value))
    }

    @Test("Invalid combined-mark bytes fail closed instead of showing unbranded Apple data")
    func invalidCombinedMarkFailsClosed() async {
        let recorder = WeatherMarkRequestRecorder(
            data: Data("not-an-image".utf8),
            contentType: "text/plain"
        )
        let loader = WeatherAttributionMarkLoader(loader: recorder.load)

        await #expect(throws: WeatherProviderError.decoding(
            "WeatherKit combined mark was unavailable"
        )) {
            _ = try await loader.hydrate(Self.validAttribution)
        }
    }

    @Test("Combined-mark downloads reject an insecure final redirect URL")
    func combinedMarkRejectsInsecureFinalURL() async {
        let recorder = WeatherMarkRequestRecorder(
            data: Self.validPNG,
            responseURL: URL(string: "http://weatherkit.apple.com/assets/mark.png")!
        )
        let loader = WeatherAttributionMarkLoader(loader: recorder.load)

        await #expect(throws: WeatherProviderError.decoding(
            "WeatherKit combined mark was unavailable"
        )) {
            _ = try await loader.hydrate(Self.validAttribution)
        }
    }

    @Test("Live combined-mark downloads reject known oversized bodies before reading")
    func combinedMarkExpectedLengthCap() {
        #expect(WeatherAttributionMarkLoader.acceptsExpectedContentLength(-1))
        #expect(WeatherAttributionMarkLoader.acceptsExpectedContentLength(2 * 1_024 * 1_024))
        #expect(!WeatherAttributionMarkLoader.acceptsExpectedContentLength(
            (2 * 1_024 * 1_024) + 1
        ))
    }

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

    @Test func dailyWindUsesSustainedSpeedAndGustAsPeak() {
        let wind = WeatherKitAdapter.dailyWind(
            speedMetersPerSecond: 5,
            gustMetersPerSecond: 8
        )
        let withoutGust = WeatherKitAdapter.dailyWind(
            speedMetersPerSecond: 5,
            gustMetersPerSecond: nil
        )

        #expect(wind.sustained == 5)
        #expect(wind.peak == 8)
        #expect(withoutGust.sustained == 5)
        #expect(withoutGust.peak == 5)
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

    @Test func classifiesOnlyPositiveConnectivityLossAsOffline() {
        #expect(
            WeatherKitAdapter.providerError(URLError(.notConnectedToInternet))
                == .network("offline")
        )
        #expect(
            WeatherKitAdapter.providerError(URLError(.timedOut))
                == .serviceUnavailable
        )
        #expect(
            WeatherKitAdapter.providerError(WeatherKitFixtureError.unknown)
                == .serviceUnavailable
        )
    }

    @Test func providerPreservesCancellation() async {
        let provider = WeatherKitProvider(
            worker: { _, _, _ in throw CancellationError() },
            attributionWorker: { Self.validAttribution }
        )

        await #expect(throws: CancellationError.self) {
            _ = try await provider.forecast(
                for: CLLocation(latitude: 30.29, longitude: -86)
            )
        }
    }

    @Test func providerPreservesURLCancellation() async {
        let provider = WeatherKitProvider(
            worker: { _, _, _ in throw URLError(.cancelled) },
            attributionWorker: { Self.validAttribution }
        )

        do {
            _ = try await provider.forecast(
                for: CLLocation(latitude: 30.29, longitude: -86)
            )
            Issue.record("Expected URL cancellation")
        } catch let error as URLError {
            #expect(error.code == .cancelled)
        } catch {
            Issue.record("Expected URLError.cancelled, got \(error)")
        }
    }

    private static let validAttribution = WeatherProviderAttribution(
        providerKind: .appleWeather,
        serviceName: "Apple Weather",
        legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
        combinedMarkLightURL: URL(string: "https://weatherkit.apple.com/assets/light.png")!,
        combinedMarkDarkURL: URL(string: "https://weatherkit.apple.com/assets/dark.png")!,
        legalText: "Weather data sources and legal attribution"
    )

    private static let validPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL9WQAAAABJRU5ErkJggg=="
    )!
}

private actor WeatherMarkRequestRecorder {
    private(set) var requests: [URLRequest] = []
    private let data: Data
    private let contentType: String
    private let responseURL: URL?

    init(
        data: Data,
        contentType: String = "image/png",
        responseURL: URL? = nil
    ) {
        self.data = data
        self.contentType = contentType
        self.responseURL = responseURL
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: responseURL ?? request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!
        return (data, response)
    }
}

private enum WeatherKitFixtureError: Error {
    case unknown
}
