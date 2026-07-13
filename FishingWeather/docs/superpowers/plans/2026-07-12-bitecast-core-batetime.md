# BiteCast Core and BiteTime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Phase 1 of the approved redesign: resilient weather, normalized location and units, a polished five-destination shell, interactive BiteTime, Pro Forecast, and Best Bait Today.

**Architecture:** View-facing code consumes provider-neutral weather snapshots. A provider chain tries WeatherKit, then the National Weather Service for supported U.S. points, then a matching disk cache. BiteTime uses one hourly series and one selected date across the chart, cells, matrix, fishing score, and bait context.

**Tech Stack:** Swift 6.0, SwiftUI, Observation, Charts, WeatherKit, MapKit, Foundation Models, Core Location, URLSession, Swift Testing, XCUITest, XcodeGen, iOS 26.5.

## Global Constraints

- Deployment target: iOS 26.5; Swift 6.0 with complete strict concurrency.
- Add no package dependency.
- Preserve catch JSON/photos, saved spots, settings, regulations, and stable identifiers.
- WeatherKit is primary, NWS is the U.S. fallback, matching cache is last.
- Never display coordinates as the primary location title.
- Round displayed temperatures to whole degrees; retain raw values for calculations.
- Fishing score and solunar calculations remain deterministic.
- Bait generation uses on-device Apple Foundation Models with a labeled deterministic fallback.
- Release builds contain no long-lived Replicate, Amazon, or eBay credentials.
- Every async store rejects stale results.
- Follow red-green TDD and commit every task independently.
- Do not push until the Phase 1 verification gate passes.

## File Map

**Create**

- `Sources/Models/LocationDescriptor.swift`
- `Sources/Models/WeatherSnapshot.swift`
- `Sources/Models/ForecastSelection.swift`
- `Sources/Services/WeatherUnits.swift`
- `Sources/Services/WeatherProvider.swift`
- `Sources/Services/WeatherKitProvider.swift`
- `Sources/Services/NWSWeatherProvider.swift`
- `Sources/Services/LocalAstronomyProvider.swift`
- `Sources/Views/BiteTimeView.swift`
- `Sources/Views/BiteTimeHero.swift`
- `Sources/Views/InteractiveForecastChart.swift`
- `Sources/Views/ProForecastMatrix.swift`
- `Sources/Views/BestBaitTodayView.swift`
- `Sources/Views/CommunityPlaceholderView.swift`
- `Sources/Views/YouView.swift`
- `Tests/LocationDescriptorTests.swift`
- `Tests/WeatherUnitsTests.swift`
- `Tests/WeatherProviderChainTests.swift`
- `Tests/WeatherKitAdapterTests.swift`
- `Tests/NWSWeatherProviderTests.swift`
- `Tests/LocalAstronomyProviderTests.swift`
- `Tests/ForecastSelectionTests.swift`
- `Tests/BestBaitContextTests.swift`
- `Tests/NavigationContractTests.swift`

**Modify**

- `Sources/Services/LocationManager.swift`
- `Sources/Services/WeatherStore.swift`
- `Sources/Services/WeatherSnapshots.swift`
- `Sources/Models/FishingConditions.swift`
- `Sources/Models/PressureReading.swift`
- `Sources/Models/MoonPhase+Display.swift`
- `Sources/Services/FishingScorer.swift`
- `Sources/Services/TripForecastLoader.swift`
- `Sources/Services/BaitEngine.swift`
- `Sources/Views/BiteCastTheme.swift`
- `Sources/Views/GlassCard.swift`
- `Sources/Views/MainTabView.swift`
- `Sources/Views/CurrentConditionsView.swift`
- `Sources/Views/WeatherTheme.swift`
- `Sources/Views/WeatherAlertsView.swift`
- `Sources/Views/WindCard.swift`
- `Sources/Views/HourlyForecastView.swift`
- `Sources/Views/DailyForecastView.swift`
- `Sources/Views/FishingCharts.swift`
- `Sources/Views/FishingView.swift`
- `Sources/Views/LogCatchView.swift`
- `Sources/Views/BaitEngineView.swift`
- `Sources/Views/WeatherDashboardView.swift`
- `Sources/Views/DebugPreviewHost.swift`
- `Sources/App/BiteCastApp.swift`
- `UITests/GlassPassUITests.swift`
- `README.md`

---

### Task 1: Normalize Location Labels and Weather Units

**Files**

- Create: `Sources/Models/LocationDescriptor.swift`
- Create: `Sources/Services/WeatherUnits.swift`
- Modify: `Sources/Services/LocationManager.swift:11-168`
- Modify: `Sources/Views/MainTabView.swift:11-15`
- Test: `Tests/LocationDescriptorTests.swift`
- Test: `Tests/WeatherUnitsTests.swift`

**Interfaces**

- Produces: `LocationDescriptor.make(city:stateCode:featureName:)`
- Produces: `WeatherUnits.wholeTemperature(_:locale:)`
- Produces: `WeatherUnits.value(_:unit:)`
- Produces: `LocationManager.descriptor`

- [ ] **Step 1: Write failing tests**

```swift
import Foundation
import Testing
@testable import BiteCast

@Suite("Location descriptor")
struct LocationDescriptorTests {
    @Test func composesCityAndState() {
        let value = LocationDescriptor.make(city: " Inlet Beach ", stateCode: "fl", featureName: nil)
        #expect(value.displayName == "Inlet Beach, FL")
    }

    @Test func rejectsCoordinateFeatureName() {
        let value = LocationDescriptor.make(
            city: nil,
            stateCode: "FL",
            featureName: "30.2938° N, 86.0049° W"
        )
        #expect(value.displayName == "Current Location")
        #expect(value.subtitle == "FL")
    }

    @Test func preservesNamedFeature() {
        let value = LocationDescriptor.make(city: nil, stateCode: "FL", featureName: "Phillips Inlet")
        #expect(value.displayName == "Phillips Inlet")
        #expect(value.subtitle == "FL")
    }
}

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
```

- [ ] **Step 2: Run tests and confirm missing-symbol failure**

```bash
xcodebuild test -project BiteCast.xcodeproj -scheme BiteCast \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:BiteCastTests/LocationDescriptorTests \
  -only-testing:BiteCastTests/WeatherUnitsTests
```

Expected: compile failure because the two production types do not exist.

- [ ] **Step 3: Implement the pure contracts**

```swift
import Foundation

struct LocationDescriptor: Equatable, Sendable {
    let city: String?
    let stateCode: String?
    let featureName: String?
    let displayName: String
    let subtitle: String?

    static func make(city: String?, stateCode: String?, featureName: String?) -> Self {
        let city = clean(city)
        let state = clean(stateCode)?.uppercased()
        let feature = clean(featureName).flatMap { coordinateLike($0) ? nil : $0 }

        if let city {
            return Self(
                city: city,
                stateCode: state,
                featureName: feature,
                displayName: state.map { "\(city), \($0)" } ?? city,
                subtitle: feature == city ? nil : feature
            )
        }
        if let feature {
            return Self(
                city: nil,
                stateCode: state,
                featureName: feature,
                displayName: feature,
                subtitle: state
            )
        }
        return Self(
            city: nil,
            stateCode: state,
            featureName: nil,
            displayName: "Current Location",
            subtitle: state
        )
    }

    private static func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func coordinateLike(_ value: String) -> Bool {
        if value.contains("°") && value.contains(",") { return true }
        let parts = value.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return parts.count == 2 && parts.allSatisfy { Double($0) != nil }
    }
}
```

```swift
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
```

Update `LocationManager.GeocodeResult` to include `featureName`, expose `descriptor`, retain the prior valid descriptor while a new geocode is pending, and make all current-location labels use it.

- [ ] **Step 4: Run the focused suites plus `LocationStateTests`**

Expected: all selected tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/LocationDescriptor.swift Sources/Services/WeatherUnits.swift \
  Sources/Services/LocationManager.swift Sources/Views/MainTabView.swift \
  Tests/LocationDescriptorTests.swift Tests/WeatherUnitsTests.swift
git commit -m "Feature: normalize locations and weather units"
```

### Task 2: Add Provider-Neutral Weather Values and Fallback Chain

**Files**

- Create: `Sources/Models/WeatherSnapshot.swift`
- Create: `Sources/Services/WeatherProvider.swift`
- Test: `Tests/WeatherProviderChainTests.swift`

**Interfaces**

- Produces: `WeatherSnapshot`
- Produces: `WeatherProvider.forecast(for:)`
- Produces: `WeatherProviderChain.forecast(for:)`

- [ ] **Step 1: Write failing chain tests**

```swift
import CoreLocation
import Testing
@testable import BiteCast

@Suite("Weather provider chain")
struct WeatherProviderChainTests {
    @Test func fallsThroughAndMarksFallback() async throws {
        let primary = StubProvider(result: .failure(WeatherProviderError.authentication))
        let fallback = StubProvider(result: .success(.fixture(source: .nws)))
        let result = try await WeatherProviderChain(providers: [primary, fallback])
            .forecast(for: CLLocation(latitude: 30.29, longitude: -86.00))
        #expect(result.provenance.source == .nws)
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
}
```

The test file defines a private `StubProvider` and complete one-hour `WeatherSnapshot.fixture`.

- [ ] **Step 2: Run the focused suite**

Expected: missing weather/provider symbols.

- [ ] **Step 3: Implement canonical snapshot types**

```swift
import Foundation

enum WeatherSource: String, Codable, Sendable {
    case weatherKit
    case nws
    case cache
}

struct WeatherProvenance: Codable, Equatable, Sendable {
    let source: WeatherSource
    let fetchedAt: Date
    let isFallback: Bool
    let attribution: String?
}

struct WindSnapshot: Codable, Equatable, Sendable {
    let directionDegrees: Double
    let speedMetersPerSecond: Double
    let gustMetersPerSecond: Double?
}

struct CurrentConditionsSnapshot: Codable, Equatable, Sendable {
    let date: Date
    let temperatureCelsius: Double
    let apparentTemperatureCelsius: Double
    let dewPointCelsius: Double?
    let humidityFraction: Double?
    let pressureHPa: Double?
    let visibilityMeters: Double?
    let uvIndex: Int?
    let conditionText: String
    let symbolName: String
    let wind: WindSnapshot
}

struct HourlyWeatherPoint: Identifiable, Codable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let temperatureCelsius: Double
    let apparentTemperatureCelsius: Double?
    let dewPointCelsius: Double?
    let humidityFraction: Double?
    let pressureHPa: Double?
    let visibilityMeters: Double?
    let uvIndex: Int?
    let cloudCoverFraction: Double?
    let precipitationChance: Double?
    let precipitationMM: Double?
    let conditionText: String
    let symbolName: String
    let wind: WindSnapshot
}

struct DailyWeatherPoint: Identifiable, Codable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let lowCelsius: Double
    let highCelsius: Double
    let precipitationChance: Double?
    let conditionText: String
    let symbolName: String
    let windPeakMetersPerSecond: Double?
}

struct AstronomySnapshot: Codable, Equatable, Sendable {
    let sunrise: Date?
    let sunset: Date?
    let moonrise: Date?
    let moonset: Date?
    let moonTransit: Date?
    let moonPhaseFraction: Double?

    static let empty = Self(
        sunrise: nil,
        sunset: nil,
        moonrise: nil,
        moonset: nil,
        moonTransit: nil,
        moonPhaseFraction: nil
    )
}
```

Add Codable coordinate, alert, and `WeatherSnapshot` values. Implement typed errors for authentication, network, rate limit, service outage, unsupported region, decoding, and aggregate failure. The chain rethrows cancellation, tries providers in order, and marks non-primary success as fallback.

- [ ] **Step 4: Run chain tests**

Expected: fallback, cancellation, and aggregate-failure cases pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/WeatherSnapshot.swift Sources/Services/WeatherProvider.swift \
  Tests/WeatherProviderChainTests.swift
git commit -m "Feature: add provider-neutral weather snapshots"
```

### Task 3: Add the WeatherKit Adapter

**Files**

- Create: `Sources/Services/WeatherKitProvider.swift`
- Test: `Tests/WeatherKitAdapterTests.swift`

**Interfaces**

- Consumes: Task 2 snapshot types.
- Produces: `WeatherKitProvider: WeatherProvider`.
- Produces: pure `WeatherKitAdapter` scalar helpers.

- [ ] **Step 1: Write failing adapter tests**

```swift
import Testing
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
    }
}
```

- [ ] **Step 2: Run and confirm missing-adapter failure**

- [ ] **Step 3: Implement adapter and provider**

```swift
enum WeatherKitAdapter {
    static func fraction(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func wind(
        directionDegrees: Double,
        speedMetersPerSecond: Double,
        gustMetersPerSecond: Double?
    ) -> WindSnapshot {
        WindSnapshot(
            directionDegrees: directionDegrees,
            speedMetersPerSecond: speedMetersPerSecond,
            gustMetersPerSecond: gustMetersPerSecond
        )
    }
}
```

`WeatherKitProvider` injects a service worker for tests and defaults to `WeatherService.shared`. Request current, hourly from six hours ago through 48 hours ahead, daily, and alerts. Convert all measurements to canonical Celsius, meters, meters-per-second, and hPa. Preserve condition description/symbol and daily astronomy. Map JWT/listener failures to `.authentication` and network failures to `.network`.

- [ ] **Step 4: Run adapter tests and a Debug simulator build**

Expected: tests and build pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Services/WeatherKitProvider.swift Tests/WeatherKitAdapterTests.swift
git commit -m "Feature: adapt WeatherKit to weather snapshots"
```

### Task 4: Add the National Weather Service Fallback

**Files**

- Create: `Sources/Services/NWSWeatherProvider.swift`
- Test: `Tests/NWSWeatherProviderTests.swift`

**Interfaces**

- Produces: `NWSWeatherProvider(loader:userAgent:astronomy:)`.
- Consumes: `LocalAstronomyProvider` from Task 5; use an injected astronomy closure until Task 5 lands.

- [ ] **Step 1: Write failing fixture-driven tests**

```swift
import CoreLocation
import Testing
@testable import BiteCast

@Suite("NWS provider")
struct NWSWeatherProviderTests {
    @Test func sendsRequiredUserAgent() async throws {
        let recorder = RequestRecorder(responses: NWSFixtures.minimumResponses)
        let provider = NWSWeatherProvider(
            loader: recorder.load,
            userAgent: "BiteCast/0.1 (app.choatelabs.bitecast)",
            astronomy: { _, _ in .empty }
        )
        _ = try await provider.forecast(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )
        #expect(
            await recorder.requests.first?.value(forHTTPHeaderField: "User-Agent")
                == "BiteCast/0.1 (app.choatelabs.bitecast)"
        )
    }

    @Test func decodesHourlyAndObservation() async throws {
        let provider = NWSWeatherProvider(
            loader: RequestRecorder(responses: NWSFixtures.minimumResponses).load,
            userAgent: "BiteCastTests/1.0 (app.choatelabs.bitecast.tests)",
            astronomy: { _, _ in .empty }
        )
        let value = try await provider.forecast(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )
        #expect(value.provenance.source == .nws)
        #expect(abs((value.hourly.first?.temperatureCelsius ?? 0) - 27.7778) < 0.001)
        #expect(value.current.pressureHPa == 1019)
    }
}
```

Inline fixtures cover `/points`, discovered hourly/daily URLs, observation stations/latest, and active point alerts.

- [ ] **Step 2: Run and confirm missing-provider failure**

- [ ] **Step 3: Implement the request graph**

```swift
struct NWSWeatherProvider: WeatherProvider {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias AstronomyWorker = @Sendable (CLLocation, Date) -> AstronomySnapshot

    let loader: Loader
    let userAgent: String
    let astronomy: AstronomyWorker

    func forecast(for location: CLLocation) async throws -> WeatherSnapshot {
        let point = try await loadPoint(location)
        async let hourly = loadHourly(point.properties.forecastHourly)
        async let daily = loadDaily(point.properties.forecast)
        async let observation = loadObservation(point.properties.observationStations)
        async let alerts = loadAlerts(location)
        return try await assemble(
            location: location,
            hourly: hourly,
            daily: daily,
            observation: observation,
            alerts: alerts,
            astronomy: astronomy(location, .now)
        )
    }
}
```

Every request sets `Accept: application/geo+json` and User-Agent, validates HTTP status, preserves cancellation, parses ISO-8601 times and NWS wind ranges, and converts canonical units. Map 404 outside coverage to `.unsupportedRegion`, 429 to `.rateLimited`, and 5xx to `.serviceUnavailable`. Missing station observations use first-hour current values without inventing pressure.

- [ ] **Step 4: Add and pass partial/error tests**

Cover null gust, absent observation, missing pressure, unsupported point, 429, malformed JSON, and cancellation.

- [ ] **Step 5: Commit**

```bash
git add Sources/Services/NWSWeatherProvider.swift Tests/NWSWeatherProviderTests.swift
git commit -m "Feature: add National Weather Service fallback"
```

### Task 5: Add Deterministic Local Astronomy

**Files**

- Create: `Sources/Services/LocalAstronomyProvider.swift`
- Test: `Tests/LocalAstronomyProviderTests.swift`

**Interfaces**

- Produces: `LocalAstronomyProvider.snapshot(for:date:calendar:)`.

- [ ] **Step 1: Write failing deterministic tests**

```swift
import CoreLocation
import Foundation
import Testing
@testable import BiteCast

@Suite("Local astronomy")
struct LocalAstronomyProviderTests {
    @Test func returnsSolarAndMoonValues() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let date = ISO8601DateFormatter().date(from: "2026-06-21T12:00:00Z")!
        let value = LocalAstronomyProvider().snapshot(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049),
            date: date,
            calendar: calendar
        )
        #expect(value.sunrise != nil)
        #expect(value.sunset != nil)
        #expect(value.moonPhaseFraction.map { (0...1).contains($0) } == true)
    }

    @Test func polarNoEventRemainsNil() {
        let value = LocalAstronomyProvider().snapshot(
            for: CLLocation(latitude: 89, longitude: 0),
            date: Date(timeIntervalSince1970: 1_782_028_800),
            calendar: Calendar(identifier: .gregorian)
        )
        #expect(value.sunrise == nil || value.sunset == nil)
    }
}
```

- [ ] **Step 2: Run and confirm missing-provider failure**

- [ ] **Step 3: Implement the calculations**

Use Julian-day conversion, NOAA solar equations with zenith `90.833°`, synodic phase period `29.530588853`, and hourly lunar-altitude crossing detection refined by bisection to one minute. Lunar transit is the maximum sampled altitude. Return nil when no crossing exists.

```swift
struct LocalAstronomyProvider: Sendable {
    func snapshot(
        for location: CLLocation,
        date: Date,
        calendar: Calendar = .current
    ) -> AstronomySnapshot {
        let day = JulianDay(date)
        let solar = SolarEvents.calculate(
            day: day,
            coordinate: location.coordinate,
            calendar: calendar
        )
        let lunar = LunarEvents.calculate(
            day: day,
            coordinate: location.coordinate,
            calendar: calendar
        )
        return AstronomySnapshot(
            sunrise: solar.sunrise,
            sunset: solar.sunset,
            moonrise: lunar.rise,
            moonset: lunar.set,
            moonTransit: lunar.transit,
            moonPhaseFraction: lunar.phaseFraction
        )
    }
}
```

Define `JulianDay`, `SolarEvents`, and `LunarEvents` as file-private value types in the same file. `SolarEvents.calculate` returns optional sunrise/sunset; `LunarEvents.calculate` returns optional rise/set/transit plus a clamped phase fraction. All trigonometric inputs are converted explicitly between degrees and radians.

- [ ] **Step 4: Add fixed UTC fixtures**

Validate Florida, Minnesota, and Alaska. Solar events must be within five minutes; lunar events within 20 minutes. Verify repeatability and nil polar events.

- [ ] **Step 5: Commit**

```bash
git add Sources/Services/LocalAstronomyProvider.swift Tests/LocalAstronomyProviderTests.swift
git commit -m "Feature: add local astronomy fallback"
```

### Task 6: Refactor WeatherStore and Fishing Facts

**Files**

- Modify: `Sources/Services/WeatherStore.swift`
- Modify: `Sources/Services/WeatherSnapshots.swift`
- Modify: `Sources/Models/FishingConditions.swift`
- Modify: `Sources/Models/PressureReading.swift`
- Modify: `Sources/Models/MoonPhase+Display.swift`
- Modify: `Sources/Services/FishingScorer.swift`
- Modify: `Sources/Services/TripForecastLoader.swift`
- Modify: `Sources/Views/WeatherTheme.swift`
- Modify: `Sources/Views/WeatherAlertsView.swift`
- Modify: `Sources/Views/WindCard.swift`
- Modify: `Sources/Views/CurrentConditionsView.swift`
- Modify: `Sources/Views/HourlyForecastView.swift`
- Modify: `Sources/Views/DailyForecastView.swift`
- Modify: `Sources/Views/LogCatchView.swift`
- Modify: `Sources/App/BiteCastApp.swift`
- Test: `Tests/WeatherSnapshotsTests.swift`
- Test: `Tests/AsyncStateIdentityTests.swift`
- Test: `Tests/FishingScorerTests.swift`

**Interfaces**

- Produces: `WeatherStore.snapshot`, `provenance`, `hasData(for:)`.
- Produces: `FishingConditions.make(snapshot:now:)`.

- [ ] **Step 1: Change tests to require neutral snapshots**

```swift
@Test @MainActor func newerNeutralSnapshotWins() async {
    let store = WeatherStore(worker: { location, _ in
        if location.coordinate.latitude == 30 {
            try await Task.sleep(for: .milliseconds(80))
        }
        return .fixture(latitude: location.coordinate.latitude)
    })
    async let old: Void = store.load(
        for: CLLocation(latitude: 30, longitude: -86)
    )
    async let new: Void = store.load(
        for: CLLocation(latitude: 31, longitude: -87)
    )
    _ = await (old, new)
    #expect(store.snapshot?.coordinate.latitude == 31)
}
```

Pin provenance persistence, cancellation, typed authentication errors, matching geo-tile cache, and stale-result rejection.

- [ ] **Step 2: Run changed tests and observe failures**

- [ ] **Step 3: Refactor store and downstream models**

Replace separate WeatherKit properties with `WeatherSnapshot?`. Preserve load ID and 15-minute TTL. Install a chain containing WeatherKit and NWS in `BiteCastApp`. Convert `FishingConditions`, pressure analysis, scoring, trip loading, alert display, wind display, current/hourly/daily views, catch snapshots, and moon display to canonical scalars. Persist a versioned neutral snapshot atomically; back up undecodable prior data.

- [ ] **Step 4: Run all unit tests**

Expected: all pass. WeatherKit types remain only in `WeatherKitProvider`, WeatherKit adapter tests, and unavoidable presentation adapters removed before commit.

- [ ] **Step 5: Commit**

```bash
git add Sources/Services/WeatherStore.swift Sources/Services/WeatherSnapshots.swift \
  Sources/Models/FishingConditions.swift Sources/Models/PressureReading.swift \
  Sources/Models/MoonPhase+Display.swift Sources/Services/FishingScorer.swift \
  Sources/Services/TripForecastLoader.swift Sources/Views/WeatherTheme.swift \
  Sources/Views/WeatherAlertsView.swift Sources/Views/WindCard.swift \
  Sources/Views/CurrentConditionsView.swift Sources/Views/HourlyForecastView.swift \
  Sources/Views/DailyForecastView.swift Sources/Views/LogCatchView.swift \
  Sources/App/BiteCastApp.swift Tests/WeatherSnapshotsTests.swift \
  Tests/AsyncStateIdentityTests.swift Tests/FishingScorerTests.swift
git commit -m "Refactor: make fishing conditions provider-neutral"
```

### Task 7: Add the Polished Five-Destination Shell

**Files**

- Modify: `Sources/Views/BiteCastTheme.swift`
- Modify: `Sources/Views/GlassCard.swift`
- Modify: `Sources/Views/MainTabView.swift`
- Create: `Sources/Views/CommunityPlaceholderView.swift`
- Create: `Sources/Views/YouView.swift`
- Modify: `Sources/Views/DebugPreviewHost.swift`
- Test: `Tests/NavigationContractTests.swift`
- Test: `UITests/GlassPassUITests.swift`

**Interfaces**

- Produces destinations: `community`, `map`, `biteTime`, `you`.
- Produces accessibility IDs: `tab.community`, `tab.map`, `action.logCatch`, `tab.biteTime`, `tab.you`.

- [ ] **Step 1: Write failing contract tests**

```swift
import Testing
@testable import BiteCast

@Suite("Navigation contract")
struct NavigationContractTests {
    @Test func permanentDestinationsAreStable() {
        #expect(
            AppDestination.allCases.map(\.rawValue)
                == ["community", "map", "biteTime", "you"]
        )
    }
}
```

Change UI tests to require four destinations and the central Log Catch action.

- [ ] **Step 2: Run and observe failures**

- [ ] **Step 3: Implement navigation and visual tokens**

Create `AppDestination`. Assemble Community, Map from existing Spots, BiteTime, and You. Overlay a central Log Catch button in the tab-bar safe area and present `LogCatchView` without changing the selected destination. Rehome Catch Log, Guide, Scout, saved spots, and Settings in You. Community shows an honest private/local placeholder, never fake posts.

Use native rounded/sans typography for language, monospaced digits only for aligned measurements. Remove global card scroll fading. Use condition-aware backgrounds and reserve glass for floating controls, selected chips, and the tab bar.

- [ ] **Step 4: Run unit/UI tests and build**

Expected: every destination is reachable and Log Catch opens/closes independently.

- [ ] **Step 5: Commit**

```bash
git add Sources/Views/BiteCastTheme.swift Sources/Views/GlassCard.swift \
  Sources/Views/MainTabView.swift Sources/Views/CommunityPlaceholderView.swift \
  Sources/Views/YouView.swift Sources/Views/DebugPreviewHost.swift \
  Tests/NavigationContractTests.swift UITests/GlassPassUITests.swift
git commit -m "Feature: add polished five-destination shell"
```

### Task 8: Add Synchronized Interactive Forecast Selection

**Files**

- Create: `Sources/Models/ForecastSelection.swift`
- Create: `Sources/Views/InteractiveForecastChart.swift`
- Modify: `Sources/Views/FishingCharts.swift`
- Modify: `Sources/Views/HourlyForecastView.swift`
- Test: `Tests/ForecastSelectionTests.swift`

**Interfaces**

- Produces: `ForecastMetric`.
- Produces: `ForecastSelection.nearest(to:in:)`.
- Produces: `ForecastPoint`.
- Produces: `ForecastSeriesBuilder.build(weather:tideSamples:species:weights:now:) -> [ForecastPoint]`.

- [ ] **Step 1: Write failing selection tests**

```swift
import Foundation
import Testing
@testable import BiteCast

@Suite("Forecast selection")
struct ForecastSelectionTests {
    @Test func snapsToNearestHour() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let points = [0, 1, 2].map {
            ForecastPoint.fixture(
                date: start.addingTimeInterval(Double($0) * 3600)
            )
        }
        let value = ForecastSelection.nearest(
            to: start.addingTimeInterval(2_000),
            in: points
        )
        #expect(value?.date == points[1].date)
    }

    @Test func emptyReturnsNil() {
        #expect(ForecastSelection.nearest(to: .now, in: []) == nil)
    }
}
```

Define a file-private `ForecastPoint.fixture(...)` test helper in
`Tests/ForecastSelectionTests.swift`; it must build a neutral
`HourlyWeatherPoint` and accept optional overrides used by Tasks 8 and 9.

- [ ] **Step 2: Run and observe missing-selection failure**

- [ ] **Step 3: Implement selection and chart**

```swift
enum ForecastMetric: String, CaseIterable, Identifiable {
    case temperature
    case wind
    case pressure
    case precipitation
    case biteScore
    var id: Self { self }
}

struct ForecastPoint: Identifiable, Equatable, Sendable {
    var id: Date { weather.date }
    let weather: HourlyWeatherPoint
    let biteScore: Int?
    let tideHeightFeet: Double?
    let tidePhase: String?
    let solunarWindow: BiteWindow?
}

enum ForecastSelection {
    static func nearest(
        to date: Date,
        in points: [ForecastPoint]
    ) -> ForecastPoint? {
        points.min {
            abs($0.weather.date.timeIntervalSince(date))
                < abs($1.weather.date.timeIntervalSince(date))
        }
    }
}
```

`ForecastSeriesBuilder` merges neutral hourly weather with deterministic hourly fishing scores, the active solunar window, and interpolated tide state without mutating the weather snapshot. Use `.chartXSelection`, selected rule/point marks, a 12-hour viewport over 24–48 hours, explicit units, and a pinned detail strip. The chart, hourly cells, and matrix share the same `[ForecastPoint]` and selected date. Trigger haptics only when the snapped date changes.

- [ ] **Step 4: Run tests and accessibility smoke**

Expected: chart/cells remain synchronized and VoiceOver can enumerate time/value pairs.

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/ForecastSelection.swift Sources/Views/InteractiveForecastChart.swift \
  Sources/Views/FishingCharts.swift Sources/Views/HourlyForecastView.swift \
  Tests/ForecastSelectionTests.swift
git commit -m "Feature: add interactive forecast selection"
```

### Task 9: Add Pro Forecast

**Files**

- Create: `Sources/Views/ProForecastMatrix.swift`
- Modify: `Sources/Views/DailyForecastView.swift`
- Modify: `Sources/Views/DebugPreviewHost.swift`
- Test: `Tests/ForecastSelectionTests.swift`
- Test: `UITests/GlassPassUITests.swift`

**Interfaces**

- Produces: `ForecastFactorRow`.
- Consumes: shared `[ForecastPoint]` and selected date.

- [ ] **Step 1: Add failing row availability test**

```swift
@Test func unsupportedFactorsAreOmitted() {
    let point = ForecastPoint.fixture(
        pressureHPa: nil,
        visibilityMeters: nil
    )
    let rows = ForecastFactorRow.rows(for: [point])
    #expect(!rows.map(\.id).contains(.pressure))
    #expect(!rows.map(\.id).contains(.visibility))
}
```

- [ ] **Step 2: Run and observe missing-row failure**

- [ ] **Step 3: Implement matrix**

Use one lazy grid with a fixed factor column and horizontally scrolling hour columns. Highlight current and selected hours with color plus shape/text. Tapping a cell updates `selectedDate`. Groups are Fishing, Weather, Wind, and Water & Sky. Omit unsupported rows. Persist collapsed groups and order. Offer day/week only within provider horizon; add no monthly precision.

- [ ] **Step 4: Run tests and UI screenshot**

Expected: selection matches Timeline; unsupported rows are absent; large Dynamic Type scrolls instead of clipping.

- [ ] **Step 5: Commit**

```bash
git add Sources/Views/ProForecastMatrix.swift Sources/Views/DailyForecastView.swift \
  Sources/Views/DebugPreviewHost.swift Tests/ForecastSelectionTests.swift \
  UITests/GlassPassUITests.swift
git commit -m "Feature: add Pro Forecast matrix"
```

### Task 10: Promote Best Bait Today

**Files**

- Modify: `Sources/Services/BaitEngine.swift`
- Create: `Sources/Views/BestBaitTodayView.swift`
- Modify: `Sources/Views/BaitEngineView.swift`
- Modify: `Sources/Views/FishingView.swift`
- Test: `Tests/BestBaitContextTests.swift`
- Test: `Tests/AsyncStateIdentityTests.swift`

**Interfaces**

- Produces: `BaitContextKey`.
- Produces: `BaitEngine.generateBestBait`.
- Produces: `BestBaitTodayView`.

- [ ] **Step 1: Write failing invalidation tests**

```swift
import Foundation
import Testing
@testable import BiteCast

@Suite("Best bait context")
struct BestBaitContextTests {
    @Test func timeBucketInvalidatesOldPick() {
        let a = BaitContextKey.make(
            species: .bass,
            locationKey: "30,-86",
            weatherFetchedAt: Date(timeIntervalSince1970: 0),
            tideGeneration: 1,
            now: Date(timeIntervalSince1970: 3_599)
        )
        let b = BaitContextKey.make(
            species: .bass,
            locationKey: "30,-86",
            weatherFetchedAt: Date(timeIntervalSince1970: 0),
            tideGeneration: 1,
            now: Date(timeIntervalSince1970: 3_601)
        )
        #expect(a != b)
    }

    @Test func allSpeciesCannotClaimBestBait() {
        #expect(!BaitContextKey.canGenerate(for: .all))
    }
}
```

- [ ] **Step 2: Run and observe missing-key failure**

- [ ] **Step 3: Refactor generation and UI**

Generate structured bait before optional prose. Store the context key with the result and invalidate on species, location, weather generation, tide generation, or hour bucket. Remove the uncalibrated confidence percentage from the primary card. Label output `On-device Apple Intelligence` with generation time.

For unavailable/failed AI, use `BaitProfile` and label it `General species guidance — not adjusted for today`. Require a specific species. Put report, Q&A, tutorials, shopping, and artwork behind `More advice`; do not start external image/shop requests when the compact card appears.

- [ ] **Step 4: Run bait and async identity tests**

Expected: stale generations cannot win and fallback works without Apple Intelligence.

- [ ] **Step 5: Commit**

```bash
git add Sources/Services/BaitEngine.swift Sources/Views/BestBaitTodayView.swift \
  Sources/Views/BaitEngineView.swift Sources/Views/FishingView.swift \
  Tests/BestBaitContextTests.swift Tests/AsyncStateIdentityTests.swift
git commit -m "Feature: promote Best Bait Today"
```

### Task 11: Assemble BiteTime

**Files**

- Create: `Sources/Views/BiteTimeView.swift`
- Create: `Sources/Views/BiteTimeHero.swift`
- Modify: `Sources/Views/CurrentConditionsView.swift`
- Modify: `Sources/Views/WeatherDashboardView.swift`
- Modify: `Sources/Views/FishingView.swift`
- Modify: `Sources/Views/MainTabView.swift`
- Modify: `Sources/Views/DebugPreviewHost.swift`
- Test: `UITests/GlassPassUITests.swift`

**Interfaces**

- Produces: one BiteTime destination with Timeline and Pro Forecast.
- Consumes: neutral store, chart selection, Best Bait Today.

- [ ] **Step 1: Add failing UI identifiers**

Require `bitetime.hero`, `bitetime.bestBait`, `bitetime.timeline`, `bitetime.proForecast`, `bitetime.planWeek`, and `bitetime.source` under `-uiTesting`.

- [ ] **Step 2: Run and observe missing elements**

- [ ] **Step 3: Implement hierarchy**

Order: descriptor, current decision, Best Bait Today, Timeline/Pro Forecast, selected species, other species, daily plan, tides/water, and weekly planner. Show source/freshness. Distinguish authentication, outage, unsupported region, network, and cache states. Use native typography and condition-aware background; keep deep weather/fishing details reachable without duplicate top-level dashboards.

- [ ] **Step 4: Run UI tests and state previews**

Expected: hero/bait precede details, Timeline and Pro Forecast share selection, and WeatherKit auth fixture visibly falls back to NWS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Views/BiteTimeView.swift Sources/Views/BiteTimeHero.swift \
  Sources/Views/CurrentConditionsView.swift Sources/Views/WeatherDashboardView.swift \
  Sources/Views/FishingView.swift Sources/Views/MainTabView.swift \
  Sources/Views/DebugPreviewHost.swift UITests/GlassPassUITests.swift
git commit -m "Feature: assemble BiteTime experience"
```

### Task 12: Verify Phase 1

**Files**

- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-07-12-bitecast-core-batetime.md` checkboxes only after evidence.

**Interfaces**

- Produces: verified checkpoint for Phase 2.

- [ ] **Step 1: Regenerate and lint**

```bash
xcodegen generate
plutil -lint Sources/Support/Info.plist Sources/Support/Info-Debug.plist \
  Sources/Support/BiteCast.entitlements Sources/Support/PrivacyInfo.xcprivacy
git diff --check
```

Expected: exit 0.

- [ ] **Step 2: Run complete clean tests**

```bash
rm -rf /tmp/gofish-phase1-tests
xcodebuild test -project BiteCast.xcodeproj -scheme BiteCast \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/gofish-phase1-tests
```

Expected: zero failures.

- [ ] **Step 3: Build three products**

```bash
xcodebuild build -project BiteCast.xcodeproj -scheme BiteCast -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/gofish-phase1-debug
xcodebuild build -project BiteCast.xcodeproj -scheme BiteCast -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/gofish-phase1-device
xcodebuild build -project BiteCast.xcodeproj -scheme BiteCast -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/gofish-phase1-release
```

Expected: all report `BUILD SUCCEEDED`.

- [ ] **Step 4: Audit signing and secrets**

```bash
codesign -d --entitlements :- \
  /tmp/gofish-phase1-device/Build/Products/Debug-iphoneos/BiteCast.app
plutil -p \
  /tmp/gofish-phase1-release/Build/Products/Release-iphoneos/BiteCast.app/Info.plist
```

Expected: WeatherKit entitlement is present; Release has no long-lived service secrets or Debug sentinels.

- [ ] **Step 5: Real-device smoke**

Install on Stephen’s iPhone with `devicectl`. Capture Community, Map, Log Catch, BiteTime Timeline, Pro Forecast, NWS source label, and You. Verify `City, ST`, whole-degree temperature, shared selection, and deterministic bait fallback.

- [ ] **Step 6: Update README and commit**

Document navigation, Apple Foundation Models, NWS fallback/User-Agent, source attribution, and remaining phases.

```bash
git add README.md docs/superpowers/plans/2026-07-12-bitecast-core-batetime.md
git commit -m "Docs: record verified BiteTime foundation"
```

- [ ] **Step 7: Independent review gate**

Dispatch correctness/security and UI/accessibility reviewers. Address evidence-backed findings, rerun affected tests, and rerun the complete suite if production code changes.

---

## Execution Handoff

The user selected continuous agent-driven execution. Use `superpowers:subagent-driven-development`: one fresh implementation agent per task, then specification review and code-quality review before advancing. Tasks that share files are sequential. The next master phase starts only after Task 12 evidence passes.
