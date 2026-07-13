# BiteTime Review Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct every formal Task 11 review finding so BiteTime remains truthful for stale forecasts, shares the exact selected forecast reference across details, uses one forecast timezone, classifies connectivity errors conservatively, and visibly ages source freshness.

**Architecture:** Keep provider and cache semantics provider-neutral, add a selected-point constructor for `FishingConditions`, and pass one immutable reference date/timezone from `BiteTimeView` into every dependent detail. Use periodic SwiftUI timelines only at source freshness presentation boundaries; fixed debug previews retain their injected date. Exercise the NWS fallback UI through a real primary-authentication-to-fallback `WeatherProviderChain`.

**Tech Stack:** Swift 6.0, SwiftUI, Observation, Charts, Foundation, Swift Testing, XCUITest, XcodeGen, iOS 26.5.

## Global Constraints

- Deployment target: iOS 26.5; Swift 6.0 with complete strict concurrency.
- Add no package dependency.
- WeatherKit remains primary, NWS remains fallback, and a bounded matching cache remains last.
- Never describe an arbitrary provider failure as offline; only positively classified connectivity failures use offline copy.
- Never display `Right now` for a stale cached forecast.
- Timeline, Pro Forecast, Fishing Details, pressure, tides, astronomy, score, and bait all consume the same selected `ForecastPoint` and reference date.
- Tide axes, rows, and accessibility text use the forecast location timezone.
- Source freshness updates at least once per minute while either BiteTime or Weather Details remains idle.
- Best Bait Today appears immediately after the BiteTime hero.
- Saved-spot accessibility retains both its title and subtitle.
- Follow red-green TDD, rerun all Task 11 gates, do not push or merge.

---

### Task 1: Selected Forecast Reference and Fishing Details

**Files:**
- Modify: `Sources/Models/FishingConditions.swift`
- Modify: `Sources/Views/FishingView.swift`
- Modify: `Sources/Views/BiteTimeView.swift`
- Test: `Tests/ForecastSelectionTests.swift`
- Test: `Tests/BiteTimePresentationTests.swift`

**Interfaces:**
- Consumes: `ForecastPoint`, `WeatherSnapshot`, forecast `Calendar`/timezone.
- Produces: `FishingConditions.make(snapshot:forecastPoint:calendar:)` and `FishingView.referenceDate`/`forecastTimeZone`.

- [ ] **Step 1: Write failing selected-point tests**

```swift
@Test("Fishing conditions use the exact selected hour and selected forecast day")
func selectedFishingConditions() {
    let value = FishingConditions.make(
        snapshot: snapshotWhoseCurrentAndSelectedHourDiffer,
        forecastPoint: selectedPoint,
        calendar: forecastCalendar
    )
    #expect(value.pressure.pressure?.value == selectedPoint.weather.pressureHPa)
    #expect(value.wind == selectedPoint.weather.wind)
    #expect(value.uvIndex == selectedPoint.weather.uvIndex)
    #expect(value.sunrise == selectedDayAstronomy.sunrise)
    #expect(value.sunset == selectedDayAstronomy.sunset)
}
```

Add contract assertions that `BiteWindowsCard`, `TideCard`, and `PressureTrendChart` receive the selected `referenceDate`, with no `.now` fallback in the deep-detail path.

- [ ] **Step 2: Run the focused suites and verify RED**

```bash
xcodebuild test -project BiteCast.xcodeproj -scheme BiteCast \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:BiteCastTests/ForecastSelectionTests \
  -only-testing:BiteCastTests/BiteTimePresentationTests
```

Expected: compile/assertion failure because the selected-point constructor and deep-detail reference arguments do not exist.

- [ ] **Step 3: Implement the minimal shared-reference path**

```swift
static func make(
    snapshot: WeatherSnapshot,
    forecastPoint: ForecastPoint,
    calendar: Calendar
) -> FishingConditions {
    let astronomy = snapshot.daily.first {
        calendar.isDate($0.date, inSameDayAs: forecastPoint.date)
    }?.astronomy ?? snapshot.astronomy
    return FishingConditions(
        pressure: PressureReading.analyze(
            nowHPa: forecastPoint.weather.pressureHPa,
            history: snapshot.hourly.compactMap { point in
                point.pressureHPa.map { (date: point.date, hPa: $0) }
            },
            now: forecastPoint.date,
            fallback: .steady
        ),
        windows: SolunarCalculator.windows(
            moonrise: astronomy.moonrise,
            moonset: astronomy.moonset,
            on: forecastPoint.date,
            calendar: calendar
        ),
        moonPhase: LunarPhase(cycleFraction: astronomy.moonPhaseFraction),
        sunrise: astronomy.sunrise,
        sunset: astronomy.sunset,
        moonrise: astronomy.moonrise,
        moonset: astronomy.moonset,
        wind: forecastPoint.weather.wind,
        uvIndex: forecastPoint.weather.uvIndex
    )
}
```

Pass `selectedPoint.date` and `forecastTimeZone` into `FishingView`; use that reference for bite-window state, tide chart domain/Now marker, pressure chart position, and score.

- [ ] **Step 4: Rerun the focused suites and verify GREEN**

Expected: all selected tests pass and `rg 'TimelineView\(.periodic\(from: \.now|PressureTrendChart\(samples: samples, now: \.now' Sources/Views/FishingView.swift` returns no match.

---

### Task 2: Bounded Cache, Error Classification, and Ticking Freshness

**Files:**
- Modify: `Sources/Services/WeatherProvider.swift`
- Modify: `Sources/Services/WeatherStore.swift`
- Modify: `Sources/Services/WeatherSnapshots.swift`
- Modify: `Sources/Views/WeatherDashboardView.swift`
- Modify: `Sources/Views/BiteTimeView.swift`
- Test: `Tests/WeatherProviderChainTests.swift`
- Test: `Tests/WeatherSnapshotsTests.swift`
- Test: `Tests/AsyncStateIdentityTests.swift`
- Test: `Tests/BiteTimePresentationTests.swift`

**Interfaces:**
- Produces: conservative `WeatherProviderError.offline` semantics or equivalent positive connectivity predicate.
- Produces: `CachedWeatherProvider(maxAge:now:)` with a 24-hour default bound.
- Produces: freshness labels driven by an injected/fixed time or a minute `TimelineView` tick.

- [ ] **Step 1: Write failing classification, expiry, and freshness tests**

```swift
@Test("Only a positively classified connectivity error presents as offline")
func offlineClassification() {
    #expect(WeatherProviderError.from(URLError(.notConnectedToInternet)).isOffline)
    #expect(!WeatherProviderError.from(URLError(.timedOut)).isOffline)
    #expect(!WeatherProviderError.from(FixtureError.unknown).isOffline)
}

@Test("Cached provider rejects forecasts older than its maximum age")
func staleCacheRejected() async {
    let provider = CachedWeatherProvider(cache: cache, maxAge: 24 * 3_600, now: { capturedNow })
    await #expect(throws: WeatherProviderError.serviceUnavailable) {
        _ = try await provider.forecast(for: location)
    }
}

@Test("Freshness presentation changes when the minute clock advances")
func sourceFreshnessAges() {
    #expect(presentation(at: fetchedAt).freshness == "Updated just now")
    #expect(presentation(at: fetchedAt.addingTimeInterval(120)).freshness == "Updated 2 min ago")
}
```

- [ ] **Step 2: Run the focused suites and verify RED**

Expected: missing expiry/classification interface and structural freshness contract failures.

- [ ] **Step 3: Implement conservative semantics**

```swift
static func providerError(for error: any Error) -> WeatherProviderError {
    if let typed = error as? WeatherProviderError { return typed }
    if let url = error as? URLError {
        return url.code == .notConnectedToInternet
            ? .network("offline")
            : .serviceUnavailable
    }
    return .serviceUnavailable
}
```

Reject cached snapshots whose `fetchedAt` age is negative or exceeds 24 hours. Wrap BiteTime and Weather Details source status in `TimelineView(.periodic(from: .now, by: 60))`; use `fixedNow` directly in deterministic previews.

- [ ] **Step 4: Rerun the focused suites and verify GREEN**

Expected: all provider, snapshot, async-state, and presentation tests pass.

---

### Task 3: BiteTime Integration, Timezone, Accessibility, and Real Fallback Fixture

**Files:**
- Modify: `Sources/Views/BiteTimeView.swift`
- Modify: `Sources/Views/TideCard.swift`
- Modify: `Sources/Views/DebugPreviewHost.swift`
- Modify: `Tests/TideCardPresentationTests.swift`
- Modify: `Tests/BiteTimePresentationTests.swift`
- Modify: `UITests/GlassPassUITests.swift`
- Modify: `../.superpowers/sdd/task-11-report.md`
- Modify: `../.superpowers/sdd/progress.md`

**Interfaces:**
- Produces: `TideCard.eventTimeLabel(_:locale:timeZone:)` shared by rows/chart/accessibility.
- Produces: a debug worker that actually calls `WeatherProviderChain` with an authentication-failing primary and NWS fallback.

- [ ] **Step 1: Write failing timezone, order, accessibility, and chain-fixture regressions**

```swift
@Test("Tide row and chart labels use the same forecast timezone")
func tideTimezoneContract() {
    #expect(TideCard.eventTimeLabel(date, locale: enUS, timeZone: eastern) == "3:00 PM")
    #expect(TideCard.eventTimeLabel(date, locale: enUS, timeZone: central) == "2:00 PM")
}
```

Add UI assertions that the NWS fixture reports a real chain attempt marker, `bitetime.bestBait` follows the hero before the source/error block, and `bitetime.location` contains both location title and saved-spot subtitle in its accessibility value.

- [ ] **Step 2: Run focused unit/UI tests and verify RED**

Expected: missing tide row formatter/chain marker and ordering/accessibility assertions fail.

- [ ] **Step 3: Integrate the minimal fixes**

```swift
static func eventTimeLabel(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
```

Inject the forecast timezone into both BiteTime tide cards and Fishing Details, move Best Bait immediately after the hero, put the location subtitle in the accessibility value, and make the `.nws` debug worker execute the provider chain before returning the snapshot.

- [ ] **Step 4: Run focused then full verification**

```bash
xcodebuild test -project BiteCast.xcodeproj -scheme BiteCast \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
xcodebuild test -project BiteCast.xcodeproj -scheme BiteCast \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:BiteCastUITests/GlassPassUITests/testBiteTimeNWSFallbackJourney \
  -only-testing:BiteCastUITests/GlassPassUITests/testBiteTimeAccessibilityLayout
xcodebuild build -project BiteCast.xcodeproj -scheme BiteCast \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Expected: all unit and UI tests pass, new screenshots are visually inspected, the clean Debug build succeeds, and `git diff --check` is clean.

- [ ] **Step 5: Commit and request formal re-review**

```bash
git add FishingWeather/Sources FishingWeather/Tests FishingWeather/UITests \
  FishingWeather/docs/superpowers/plans/2026-07-13-batetime-review-follow-up.md \
  .superpowers/sdd/task-11-report.md .superpowers/sdd/progress.md
git commit -m "Fix: address BiteTime review findings"
```

Do not push or merge.
