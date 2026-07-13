#if DEBUG
import CoreLocation
import SwiftUI

/// Permanent deterministic visual-QA harness. It renders production components
/// without relying on live WeatherKit, GPS, tides, or network services.
/// Select a fixture with `-uiPreview <name>`.
struct DebugPreviewHost: View {
    @State private var weatherStore = WeatherStore(worker: { _, _ in
        throw WeatherProviderError.serviceUnavailable
    })
    @State private var locationManager = LocationManager()
    @State private var spotStore = SpotStore()
    @State private var catchLog = CatchLog()
    @State private var tideService = TideService()
    @State private var spotCatalog = CuratedSpotCatalog()
    @State private var osmClient = OpenStreetMapClient()
    @State private var inaturalist = INaturalistClient()
    @State private var alertSettings = AlertSettings()
    @State private var regulationStore = RegulationStore()

    var body: some View {
        if let biteTimeMode = BiteTimePreviewMode.requested {
            DebugBiteTime(mode: biteTimeMode)
        } else if CommandLine.arguments.contains("shell") {
            MainTabView()
                .environment(locationManager)
                .environment(weatherStore)
                .environment(spotStore)
                .environment(catchLog)
                .environment(regulationStore)
                .environment(tideService)
                .environment(spotCatalog)
                .environment(osmClient)
                .environment(inaturalist)
                .environment(alertSettings)
        } else if CommandLine.arguments.contains("proForecast") {
            DebugProForecast()
        } else if CommandLine.arguments.contains("guide") {
            NavigationStack { SpeciesGuideView() }
                .environment(SpotStore())
        } else if CommandLine.arguments.contains("scout") {
            NavigationStack { ScoutView() }
                .environment(weatherStore)
                .environment(SpotStore())
                .environment(LocationManager())
        } else if CommandLine.arguments.contains("log") {
            NavigationStack { CatchLogView() }
                .environment(CatchLog())
        } else if CommandLine.arguments.contains("planner") {
            DebugTripPlanner()
        } else if CommandLine.arguments.contains("tide") {
            DebugTideCard()
        } else if CommandLine.arguments.contains("scorecard") {
            DebugScoreCard()
        } else if CommandLine.arguments.contains("patterns") {
            DebugPatterns()
        } else if CommandLine.arguments.contains("settings") {
            DebugSettings()
        } else {
            Text("Unknown -uiPreview target")
        }
    }
}

private enum BiteTimePreviewMode: String, Sendable {
    case live = "biteTimeLive"
    case nws = "biteTimeNWS"
    case cache = "biteTimeCache"
    case authentication = "biteTimeAuth"
    case network = "biteTimeNetwork"
    case rateLimited = "biteTimeRateLimited"
    case outage = "biteTimeOutage"
    case unsupported = "biteTimeUnsupported"
    case loading = "biteTimeLoading"

    static var requested: Self? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "-uiPreview"),
              arguments.indices.contains(flag + 1)
        else { return nil }
        return Self(rawValue: arguments[flag + 1])
    }
}

private enum BiteTimePreviewFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let locale = Locale(identifier: "en_US_POSIX")
    static let timeZone = TimeZone(identifier: "America/New_York")!
    static let coordinate = WeatherCoordinate(
        latitude: 27.7634,
        longitude: -82.6403
    )
    static let location = CLLocation(
        latitude: coordinate.latitude,
        longitude: coordinate.longitude
    )

    static let preferenceSuiteName =
        "app.choatelabs.bitecast.debug.biteTime.v1"
    static let resetPreferenceArgument =
        "-resetBiteTimePreviewPreferences"

    @MainActor static let preferenceStore: UserDefaults = {
        guard let store = UserDefaults(suiteName: preferenceSuiteName) else {
            preconditionFailure("Unable to create isolated BiteTime preview defaults")
        }
        if CommandLine.arguments.contains(resetPreferenceArgument) {
            store.removePersistentDomain(forName: preferenceSuiteName)
        }
        return store
    }()

    static var tide: BiteTimeTideSnapshot {
        let allEvents = (0..<10).map { index in
            TideEvent(
                time: now.addingTimeInterval(Double(index * 6 - 12) * 3_600),
                kind: index.isMultiple(of: 2) ? .high : .low,
                heightFeet: index.isMultiple(of: 2) ? 3.6 : 0.7
            )
        }
        let samples = (0..<73).map { index in
            let offsetHours = Double(index - 12)
            return TideSample(
                time: now.addingTimeInterval(offsetHours * 3_600),
                heightFeet: 2.15 + 1.45 * sin(offsetHours / 2.0)
            )
        }
        return BiteTimeTideSnapshot(
            events: allEvents.filter { $0.time >= now }.prefix(4).map { $0 },
            allEvents: allEvents,
            samples: samples,
            allSamples: samples,
            stationName: "St. Petersburg, Tampa Bay",
            distanceMiles: 2.4
        )
    }

    @MainActor
    static func weatherStore(for mode: BiteTimePreviewMode) -> WeatherStore {
        WeatherStore(
            worker: { _, _ in
                switch mode {
                case .live:
                    return snapshot(
                        source: .weatherKit,
                        fetchedAt: now.addingTimeInterval(-5 * 60),
                        isFallback: false,
                        attribution: "Apple Weather"
                    )
                case .nws:
                    return try await BiteTimePreviewProviderChainFixture
                        .run()
                        .snapshot
                case .cache:
                    return snapshot(
                        source: .cache,
                        fetchedAt: now.addingTimeInterval(-20 * 60),
                        isFallback: true,
                        attribution: "Cached from National Weather Service"
                    )
                case .authentication:
                    throw WeatherProviderError.authentication
                case .network:
                    throw WeatherProviderError.from(
                        URLError(.notConnectedToInternet)
                    )
                case .rateLimited:
                    throw WeatherProviderError.rateLimited(retryAfter: 45)
                case .outage:
                    throw WeatherProviderError.serviceUnavailable
                case .unsupported:
                    throw WeatherProviderError.unsupportedRegion
                case .loading:
                    try await Task.sleep(nanoseconds: 3_600_000_000_000)
                    throw CancellationError()
                }
            },
            now: { now }
        )
    }

    static func snapshot(
        source: WeatherSource,
        fetchedAt: Date,
        isFallback: Bool,
        attribution: String?
    ) -> WeatherSnapshot {
        let astronomy = astronomy(for: now)
        return WeatherSnapshot(
            coordinate: coordinate,
            timeZoneIdentifier: timeZone.identifier,
            current: CurrentConditionsSnapshot(
                date: now,
                temperatureCelsius: 27.2,
                apparentTemperatureCelsius: 28.4,
                dewPointCelsius: 20.1,
                humidityFraction: 0.64,
                pressureHPa: 1_014.8,
                visibilityMeters: 16_100,
                uvIndex: 6,
                conditionText: "Partly cloudy",
                symbolName: "cloud.sun.fill",
                wind: WindSnapshot(
                    directionDegrees: 145,
                    speedMetersPerSecond: 4.1,
                    gustMetersPerSecond: 6.8
                )
            ),
            hourly: (0..<48).map(hourlyPoint),
            daily: (0..<7).map(dailyPoint),
            alerts: [],
            astronomy: astronomy,
            provenance: WeatherProvenance(
                source: source,
                fetchedAt: fetchedAt,
                isFallback: isFallback,
                attribution: attribution,
                providerAttribution: source == .weatherKit
                    ? appleAttribution
                    : .nationalWeatherService,
                expiresAt: now.addingTimeInterval(30 * 60)
            )
        )
    }

    fileprivate static let appleAttribution = WeatherProviderAttribution(
        providerKind: .appleWeather,
        serviceName: "Apple Weather",
        legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
        combinedMarkLightURL: URL(string: "https://weatherkit.apple.com/assets/branding/en/Apple_Weather_blk_en_3X_090122.png")!,
        combinedMarkDarkURL: URL(string: "https://weatherkit.apple.com/assets/branding/en/Apple_Weather_wht_en_3X_090122.png")!,
        legalText: "Weather data sources and legal attribution",
        // Exact provider-supplied WeatherKit combined marks. Keeping both
        // variants embedded makes the offline UI fixture exercise the same
        // branded rendering path as a live or still-valid cached snapshot.
        combinedMarkLightData: previewAppleBlackMark,
        combinedMarkDarkData: previewAppleWhiteMark
    )

    private static let previewAppleWhiteMark = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAOcAAAAqCAYAAABIgkxKAAAACXBIWXMAAAWxAAAFsQGS3qTBAAAE9GlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNy4yLWMwMDAgNzkuNTY2ZWJjNWI0LCAyMDIyLzA1LzA5LTA4OjI1OjU1ICAgICAgICAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyIgeG1sbnM6cGhvdG9zaG9wPSJodHRwOi8vbnMuYWRvYmUuY29tL3Bob3Rvc2hvcC8xLjAvIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RFdnQ9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZUV2ZW50IyIgeG1wOkNyZWF0b3JUb29sPSJBZG9iZSBQaG90b3Nob3AgMjMuNCAoTWFjaW50b3NoKSIgeG1wOkNyZWF0ZURhdGU9IjIwMjItMDktMDFUMTE6MjA6NTgtMDQ6MDAiIHhtcDpNb2RpZnlEYXRlPSIyMDIyLTA5LTAxVDE1OjM1OjU1LTA0OjAwIiB4bXA6TWV0YWRhdGFEYXRlPSIyMDIyLTA5LTAxVDE1OjM1OjU1LTA0OjAwIiBkYzpmb3JtYXQ9ImltYWdlL3BuZyIgcGhvdG9zaG9wOkNvbG9yTW9kZT0iMyIgeG1wTU06SW5zdGFuY2VJRD0ieG1wLmlpZDpjMmFiNWIzZC1lY2RmLTQ4MTQtYmYxYS1jNzAxNWEzNjVkZDYiIHhtcE1NOkRvY3VtZW50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"
    )!

    private static let previewAppleBlackMark = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAOcAAAAqCAYAAABIgkxKAAAACXBIWXMAAAWxAAAFsQGS3qTBAAAE9GlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNy4yLWMwMDAgNzkuNTY2ZWJjNWI0LCAyMDIyLzA1LzA5LTA4OjI1OjU1ICAgICAgICAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyIgeG1sbnM6cGhvdG9zaG9wPSJodHRwOi8vbnMuYWRvYmUuY29tL3Bob3Rvc2hvcC8xLjAvIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RFdnQ9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZUV2ZW50IyIgeG1wOkNyZWF0b3JUb29sPSJBZG9iZSBQaG90b3Nob3AgMjMuNCAoTWFjaW50b3NoKSIgeG1wOkNyZWF0ZURhdGU9IjIwMjItMDktMDFUMTE6MjA6MDMtMDQ6MDAiIHhtcDpNb2RpZnlEYXRlPSIyMDIyLTA5LTAxVDE1OjM1OjI4LTA0OjAwIiB4bXA6TWV0YWRhdGFEYXRlPSIyMDIyLTA5LTAxVDE1OjM1OjI4LTA0OjAwIiBkYzpmb3JtYXQ9ImltYWdlL3BuZyIgcGhvdG9zaG9wOkNvbG9yTW9kZT0iMyIgeG1wTU06SW5zdGFuY2VJRD0ieG1wLmlpZDpjMzMyNWJlMi04NjhmLTRmYzctYTRiMC01OGUxNDIzZDc4NzYiIHhtcE1NOkRvY3VtZW50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"
    )!

    private static func hourlyPoint(_ hour: Int) -> HourlyWeatherPoint {
        let date = now.addingTimeInterval(Double(hour) * 3_600)
        let localHour = localHour(for: date)
        let daylight = sin(
            (Double(localHour) - 6) / 12 * .pi
        ).clamped(to: 0...1)
        let passingShower = hour == 7 || hour == 8 || hour == 31
        let temperature = 22.4 + daylight * 6.4

        return HourlyWeatherPoint(
            date: date,
            temperatureCelsius: hour == 0 ? 27.2 : temperature,
            apparentTemperatureCelsius: temperature + 1.1,
            dewPointCelsius: 19.7,
            humidityFraction: 0.72 - daylight * 0.18,
            pressureHPa: 1_015 - Double(hour) * 0.09,
            visibilityMeters: passingShower ? 10_500 : 16_100,
            uvIndex: Int((daylight * 8).rounded()),
            cloudCoverFraction: passingShower ? 0.82 : 0.34,
            precipitationChance: passingShower ? 0.48 : 0.08,
            precipitationMM: passingShower ? 1.6 : 0,
            conditionText: passingShower ? "Passing showers" : "Partly cloudy",
            symbolName: passingShower ? "cloud.sun.rain.fill" : "cloud.sun.fill",
            wind: WindSnapshot(
                directionDegrees: Double((145 + hour * 4) % 360),
                speedMetersPerSecond: 3.5 + sin(Double(hour) / 4),
                gustMetersPerSecond: 6.2 + sin(Double(hour) / 3)
            )
        )
    }

    private static func dailyPoint(_ day: Int) -> DailyWeatherPoint {
        let date = dayStart.addingTimeInterval(Double(day) * 86_400)
        let showerDay = day == 2 || day == 5
        return DailyWeatherPoint(
            date: date,
            lowCelsius: 21.4 + Double(day % 2),
            highCelsius: 28.6 + Double(day % 3) * 0.7,
            precipitationChance: showerDay ? 0.46 : 0.14,
            conditionText: showerDay ? "Scattered showers" : "Partly cloudy",
            symbolName: showerDay ? "cloud.sun.rain.fill" : "cloud.sun.fill",
            windMetersPerSecond: 4.0 + Double(day) * 0.2,
            windPeakMetersPerSecond: 7.1 + Double(day) * 0.25,
            astronomy: astronomy(for: date)
        )
    }

    private static var dayStart: Date {
        calendar.startOfDay(for: now)
    }

    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = locale
        value.timeZone = timeZone
        return value
    }

    private static func localHour(for date: Date) -> Int {
        calendar.component(.hour, from: date)
    }

    private static func astronomy(for date: Date) -> AstronomySnapshot {
        let midnight = calendar.startOfDay(for: date)
        return AstronomySnapshot(
            sunrise: midnight.addingTimeInterval(7.1 * 3_600),
            sunset: midnight.addingTimeInterval(17.8 * 3_600),
            moonrise: midnight.addingTimeInterval(19.4 * 3_600),
            moonset: midnight.addingTimeInterval(8.2 * 3_600),
            moonTransit: midnight.addingTimeInterval(1.7 * 3_600),
            moonPhaseFraction: 0.72
        )
    }
}

enum DebugWeatherFixtureAttribution {
    static let apple = BiteTimePreviewFixture.appleAttribution
}

struct BiteTimePreviewProviderChainResult: Sendable {
    let snapshot: WeatherSnapshot
    let attempts: [String]
}

/// The permanent NWS preview executes the same ordered provider-chain contract
/// as production. The attempt trace makes a direct pre-marked NWS snapshot an
/// observable test regression instead of an equivalent-looking shortcut.
enum BiteTimePreviewProviderChainFixture {
    static func run() async throws -> BiteTimePreviewProviderChainResult {
        let recorder = BiteTimePreviewProviderAttemptRecorder()
        let fallback = BiteTimePreviewFixture.snapshot(
            source: .nws,
            fetchedAt: BiteTimePreviewFixture.now.addingTimeInterval(-8 * 60),
            isFallback: false,
            attribution: "National Weather Service"
        )
        let snapshot = try await WeatherProviderChain(providers: [
            BiteTimePreviewAuthenticationProvider(recorder: recorder),
            BiteTimePreviewNWSProvider(recorder: recorder, snapshot: fallback),
        ]).forecast(for: BiteTimePreviewFixture.location)
        return BiteTimePreviewProviderChainResult(
            snapshot: snapshot,
            attempts: await recorder.recordedAttempts()
        )
    }

    static func nwsSnapshot() async throws -> WeatherSnapshot {
        try await run().snapshot
    }
}

private actor BiteTimePreviewProviderAttemptRecorder {
    private var attempts: [String] = []

    func record(_ provider: String) {
        attempts.append(provider)
    }

    func recordedAttempts() -> [String] { attempts }
}

private struct BiteTimePreviewAuthenticationProvider: WeatherProvider {
    let recorder: BiteTimePreviewProviderAttemptRecorder

    func forecast(for location: CLLocation) async throws -> WeatherSnapshot {
        await recorder.record("WeatherKit")
        throw WeatherProviderError.authentication
    }
}

private struct BiteTimePreviewNWSProvider: WeatherProvider {
    let recorder: BiteTimePreviewProviderAttemptRecorder
    let snapshot: WeatherSnapshot

    func forecast(for location: CLLocation) async throws -> WeatherSnapshot {
        await recorder.record("NWS")
        return snapshot
    }
}

private struct DebugBiteTime: View {
    private let mode: BiteTimePreviewMode
    @State private var weatherStore: WeatherStore
    @State private var locationManager: LocationManager
    @State private var spotStore: SpotStore
    @State private var catchLog: CatchLog
    @State private var tideService = TideService()
    @State private var engine: BaitEngine

    @MainActor
    init(mode: BiteTimePreviewMode) {
        self.mode = mode
        _weatherStore = State(
            initialValue: BiteTimePreviewFixture.weatherStore(for: mode)
        )

        let locationManager = LocationManager { _ in
            LocationManager.GeocodeResult(
                placeName: "St. Petersburg",
                stateCode: "FL"
            )
        }
        locationManager.acceptLocation(BiteTimePreviewFixture.location.coordinate)
        _locationManager = State(initialValue: locationManager)

        let spotStore = SpotStore()
        if mode == .nws {
            spotStore.activate(FishingSpot(
                name: "St. Petersburg Pier",
                location: BiteTimePreviewFixture.location,
                waterType: .saltwater,
                kind: .pier,
                stateCode: "FL"
            ))
        } else {
            spotStore.select(nil)
        }
        _spotStore = State(initialValue: spotStore)

        let catchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BiteCast-BiteTime-Preview", isDirectory: true)
        if CommandLine.arguments.contains(
            BiteTimePreviewFixture.resetPreferenceArgument
        ) {
            try? FileManager.default.removeItem(at: catchDirectory)
        }
        _catchLog = State(initialValue: CatchLog(directory: catchDirectory))
        _engine = State(initialValue: BaitEngine(modelAvailability: {
            .unavailable("Deterministic preview guidance")
        }))
    }

    var body: some View {
        NavigationStack {
            BiteTimeView(
                fixedNow: BiteTimePreviewFixture.now,
                allowsAutomaticTideLoad: false,
                tideOverride: BiteTimePreviewFixture.tide,
                preferencesStore: BiteTimePreviewFixture.preferenceStore,
                initialSpecies: .bass,
                engine: engine
            )
            .navigationTitle("BiteTime")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.locale, BiteTimePreviewFixture.locale)
        .environment(\.timeZone, BiteTimePreviewFixture.timeZone)
        .environment(weatherStore)
        .environment(locationManager)
        .environment(spotStore)
        .environment(catchLog)
        .environment(tideService)
        .task(id: mode) {
            await weatherStore.load(
                for: BiteTimePreviewFixture.location,
                force: true
            )
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

enum ProForecastPreviewFixture {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static let locale = Locale(identifier: "en_US_POSIX")
    static let timeZone = TimeZone.gmt
    static let preferenceSuiteName = "app.choatelabs.bitecast.debug.proForecast.v1"
    static let resetPreferenceArgument = "-resetProForecastPreviewPreferences"

    static func dayStart(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: date)
    }

    static func nextTideTurn(after date: Date) -> TideEvent {
        let midnight = dayStart(for: date)
        let candidates: [(time: Date, kind: TideEvent.Kind, height: Double)] = [
            (midnight.addingTimeInterval(8 * 3_600), .high, 3.4),
            (midnight.addingTimeInterval(20 * 3_600), .low, 0.8),
            (midnight.addingTimeInterval(32 * 3_600), .high, 3.4),
        ]
        guard let next = candidates.first(where: { $0.time > date }) else {
            preconditionFailure("Pro Forecast preview requires a future tide turn")
        }
        return TideEvent(
            time: next.time,
            kind: next.kind,
            heightFeet: next.height
        )
    }

    static var points: [ForecastPoint] {
        let major = BiteWindow(
            period: .major,
            peak: start.addingTimeInterval(6 * 3_600),
            cause: "Moon overhead"
        )
        return (0..<48).map { hour in
            let date = start.addingTimeInterval(Double(hour) * 3_600)
            let midnight = dayStart(for: date)
            let temperature = 21 + 4 * sin(Double(hour) / 5)
            let tideRate = 0.7 * cos(Double(hour) / 2.4)
            return ForecastPoint(
                weather: HourlyWeatherPoint(
                    date: date,
                    temperatureCelsius: temperature,
                    apparentTemperatureCelsius: temperature + 1.2,
                    dewPointCelsius: temperature - 4.5,
                    humidityFraction: 0.58 + 0.14 * sin(Double(hour) / 6),
                    pressureHPa: 1_016 - Double(hour) * 0.22,
                    visibilityMeters: 15_500,
                    uvIndex: max(0, 7 - abs(12 - hour % 24)),
                    cloudCoverFraction: 0.18 + 0.25 * sin(Double(hour) / 4),
                    precipitationChance: hour % 9 == 0 ? 0.32 : 0,
                    precipitationMM: hour % 9 == 0 ? 1.4 : 0,
                    conditionText: hour % 9 == 0
                        ? "Passing showers"
                        : "Partly cloudy",
                    symbolName: hour % 9 == 0
                        ? "cloud.rain.fill"
                        : "cloud.sun.fill",
                    wind: WindSnapshot(
                        directionDegrees: Double((150 + hour * 6) % 360),
                        speedMetersPerSecond: 3.6 + sin(Double(hour) / 3),
                        gustMetersPerSecond: 6.2 + sin(Double(hour) / 2)
                    )
                ),
                biteScore: min(94, 44 + (hour * 7) % 48),
                tideHeightFeet: 2.1 + 1.3 * sin(Double(hour) / 2.4),
                tidePhase: tideRate > 0.08
                    ? "Rising"
                    : (tideRate < -0.08 ? "Falling" : "Slack"),
                solunarWindow: major.isActive(at: date) ? major : nil,
                pressureTendency: .falling,
                moonPhase: .full,
                sunrise: midnight.addingTimeInterval(6.5 * 3_600),
                sunset: midnight.addingTimeInterval(18.4 * 3_600),
                tideRateFeetPerHour: tideRate,
                nextTideTurn: nextTideTurn(after: date)
            )
        }
    }

    @MainActor static let preferenceStore: UserDefaults = {
        guard let store = UserDefaults(suiteName: preferenceSuiteName) else {
            preconditionFailure("Unable to create isolated Pro Forecast preview defaults")
        }
        if CommandLine.arguments.contains(resetPreferenceArgument) {
            store.removePersistentDomain(forName: preferenceSuiteName)
        }
        return store
    }()
}

private struct DebugProForecast: View {
    private let start = ProForecastPreviewFixture.start
    @State private var selectedDate: Date? = Date(
        timeIntervalSince1970: 1_800_000_000
    )

    var body: some View {
        ScrollView {
            ProForecastMatrix(
                points: ProForecastPreviewFixture.points,
                selectedDate: $selectedDate,
                timeZone: ProForecastPreviewFixture.timeZone,
                now: start,
                preferencesStore: ProForecastPreviewFixture.preferenceStore
            )
            .padding(16)
        }
        .background(Ink.backdrop)
        .environment(\.locale, ProForecastPreviewFixture.locale)
        .environment(\.timeZone, ProForecastPreviewFixture.timeZone)
    }
}

private struct DebugSettings: View {
    @State private var settings: AlertSettings = {
        let s = AlertSettings()
        s.preferences.enabled = true
        return s
    }()

    var body: some View {
        SettingsView().environment(settings)
    }
}

private struct DebugPatterns: View {
    private var catches: [CatchEntry] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func c(_ bait: String, _ pressure: String, _ moon: String, _ hour: Int, _ day: Int) -> CatchEntry {
            CatchEntry(date: base.addingTimeInterval(Double(day) * 86_400 + Double(hour) * 3600),
                       species: .bass, bait: bait, pressureTendency: pressure, moonPhase: moon)
        }
        return [
            c("Chatterbait", "Falling", "First Quarter", 6, 0),
            c("Chatterbait", "Falling", "First Quarter", 7, 2),
            c("Chatterbait", "Falling", "Last Quarter", 6, 5),
            c("Chatterbait", "Falling", "First Quarter", 8, 8),
            c("Chatterbait", "Falling", "First Quarter", 7, 11),
            c("Chatterbait", "Falling", "Last Quarter", 6, 12),
            c("Jig", "Falling", "First Quarter", 6, 14),
            c("Jig", "Falling", "First Quarter", 9, 17),
            c("Jig", "Steady", "First Quarter", 7, 20),
            c("Spinnerbait", "Falling", "Last Quarter", 6, 23),
            c("Spinnerbait", "Falling", "First Quarter", 15, 26),
            c("Jig", "Falling", "First Quarter", 8, 32),
        ]
    }

    var body: some View {
        YourPatternsView(
            insights: PersonalInsightsBuilder.build(from: catches, species: .bass),
            species: .bass
        )
    }
}

private struct DebugTripPlanner: View {
    private let start = Date.now

    private var outlook: WeekOutlook {
        let cal = Calendar.current
        func win(_ day: Int, _ hour: Int, _ dur: Double, _ score: Int,
                 _ conf: ScoredWindow.Confidence, _ period: BitePeriod,
                 _ factors: [String]) -> ScoredWindow {
            let d = cal.date(byAdding: .day, value: day, to: cal.startOfDay(for: start))!
            let s = d.addingTimeInterval(Double(hour) * 3600)
            return ScoredWindow(date: d, start: s, end: s.addingTimeInterval(dur * 3600),
                                score: score, confidence: conf, period: period,
                                factors: factors, species: .redfish)
        }
        return WeekOutlook(locationName: "Fort De Soto", generatedAt: start, windows: [
            win(0, 6, 1.8, 86, .high, .major, ["Major window", "Falling pressure"]),
            win(1, 7, 1.5, 78, .high, .minor, ["Minor window", "Ideal wind"]),
            win(0, 18, 1.8, 71, .high, .major, ["Dusk major", "Strong tide"]),
            win(4, 5, 1.8, 66, .low, .major, ["Major window", "Full moon"]),
            win(2, 12, 1.5, 58, .high, .minor, ["Midday minor"]),
            win(5, 19, 1.8, 52, .low, .major, ["Evening major"]),
        ])
    }

    var body: some View {
        NavigationStack {
            TripPlannerView(
                outlook: outlook,
                provenance: WeatherProvenance(
                    source: .nws,
                    fetchedAt: .now,
                    isFallback: true,
                    attribution: "National Weather Service",
                    providerAttribution: .nationalWeatherService,
                    expiresAt: .now.addingTimeInterval(30 * 60)
                )
            )
        }
    }
}

private struct DebugTideCard: View {
    private let start = Date.now.addingTimeInterval(-6 * 3600)

    private var samples: [TideSample] {
        (0..<49).map { i in
            let t = Double(i) * 0.5 // hours
            let h = 2.6 + 1.7 * sin((t / 12.42) * 2 * .pi + 1.0)
            return TideSample(time: start.addingTimeInterval(t * 3600), heightFeet: h)
        }
    }

    private var events: [TideEvent] {
        [
            TideEvent(time: start.addingTimeInterval(1.8 * 3600), kind: .low, heightFeet: 0.9),
            TideEvent(time: start.addingTimeInterval(8.0 * 3600), kind: .high, heightFeet: 4.3),
            TideEvent(time: start.addingTimeInterval(14.2 * 3600), kind: .low, heightFeet: 0.9),
            TideEvent(time: start.addingTimeInterval(20.4 * 3600), kind: .high, heightFeet: 4.3),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TideCard(
                    events: events,
                    samples: samples,
                    stationName: "Fort De Soto",
                    distanceMiles: 3,
                    isLoading: false,
                    referenceDate: start
                )
            }
            .padding(.horizontal)
            .padding(.top, 20)
        }
        .background(Ink.backdrop)
    }
}

private struct DebugScoreCard: View {
    private let score = FishingScore(factors: [
        ScoreFactor(kind: .solunar, label: "Solunar", weight: 0.25, raw: 0.92,
                    detail: "Full moon — major bite window active until 8:00 AM"),
        ScoreFactor(kind: .pressure, label: "Pressure", weight: 0.20, raw: 0.95,
                    detail: "Falling — a dropping barometer ahead of a front turns fish on"),
        ScoreFactor(kind: .wind, label: "Wind", weight: 0.15, raw: 0.85,
                    detail: "8 mph SE — light chop, good visibility under the surface"),
        ScoreFactor(kind: .tide, label: "Tide", weight: 0.25, raw: 0.90,
                    detail: "Strong moving water — prime tide. Next tide in 2 hr"),
        ScoreFactor(kind: .season, label: "Season", weight: 0.15, raw: 0.35,
                    detail: "Shoulder month for redfish"),
    ])

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private var samples: [HourSample] {
        (0..<24).map { i in
            HourSample(
                date: start.addingTimeInterval(Double(i) * 3600),
                temperatureCelsius: 23.9,
                pressureHPa: 1016 - Double(i) * 0.34,
                precipChance: 0,
                windSpeedMph: 9 + 5 * sin(Double(i) / 3.0),
                windGustMph: 14 + 7 * sin(Double(i) / 3.0)
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FishingScoreCard(score: score, tunedCount: 12)

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Barometer", systemImage: "barometer")
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("1013 hPa")
                                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                                Label("Falling", systemImage: "arrow.down.right")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Ink.bite)
                                Spacer()
                            }
                            Text("A dropping barometer ahead of a front is the textbook trigger.")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(Ink.chartDim)
                            PressureTrendChart(samples: samples,
                                               referenceDate: start.addingTimeInterval(3 * 3600))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Wind", systemImage: "wind")
                    GlassCard {
                        WindForecastChart(samples: samples,
                                          now: start.addingTimeInterval(3 * 3600))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(Ink.backdrop)
    }
}
#endif
