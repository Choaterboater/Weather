# BiteCast — Deep Dive Debug Report

**Date:** 2026-07-25
**Branch:** `claude/deep-dive-debug-report-vfs83h`
**Base commit:** `5aa82d4` ("Fix: sign device test targets automatically")
**Scope:** All 162 Swift files (~35.7k LOC) under `FishingWeather/`, plus the
XcodeGen spec, release gate, and bundled resources.

## How this pass was run

No Swift toolchain is available in this environment (`swift`, `swiftc`,
`xcodebuild`, and `xcodegen` are all absent), so **nothing here was reproduced by
compiling or running the suite**. Every finding below is a static read of the
source with the exact call chain traced by hand, and each one names the lines you
can check. Where an existing test encodes or masks the behavior, that test is
cited.

This pass deliberately looked past the areas the three prior debug passes already
hardened (async request identity, secret boundaries, file-protection
transactions, resource identity). Those held up under re-reading: `WeatherStore`,
`CatchRepository`, and `TideService` all correctly fence superseded requests,
and the astronomy math in `LocalAstronomyProvider` checks out against Meeus /
Schlyter term-by-term. The findings below are mostly a different class —
**behavior that is individually well-guarded but does not compose into the
product promise**.

---

## Summary

| # | Severity | Area | Finding |
|---|---|---|---|
| 1 | **High** | Offline cache | `CachedWeatherProvider` is unreachable in practice — its 24 h `maxAge` is dead code behind the origin provider's 30–60 min expiry |
| 2 | **High** | Scoring | Barometric pressure factor is permanently neutral on the entire NWS path |
| 3 | Medium | Performance | `BiteTimeView.forecastPoints` rebuilds the full 48-hour series ~8× per body pass, on the main actor |
| 4 | Medium | Personalization | Off-by-one at `minCatches`: UI claims "tuned to your 5 catches" while the score is un-personalized |
| 5 | Medium | NWS parsing | Today's daily forecast is silently dropped for any evening fetch |
| 6 | Medium | NWS parsing | One malformed hourly period discards the entire forecast |
| 7 | Medium | Performance | `CatchRepository` re-walks and re-`setAttributes` every photo on every save |
| 8 | Medium | Performance | `TideService.nearestStation` scans ~3,000 stations on the main actor with 2 geodesic distance computations per comparison |
| 9 | Low | Correctness | `Calendar.current` leaks into four otherwise timezone-threaded code paths |
| 10 | Low | Notifications | `UNCalendarNotificationTrigger` components carry no time zone |
| 11 | Low | Determinism | `PersonalInsights` tie-breaking depends on `Dictionary` iteration order |
| 12 | Low | Scoring | `FishingScore.overall` sums pre-rounded contributions (±2 points, can cross a band) |
| 13 | Low | Astronomy | `moonTransit` is fabricated at a day edge instead of returning `nil` (latent) |
| 14 | Low | Weather | An alert expiring seconds after fetch makes a successful fetch present as `serviceUnavailable` |
| 15 | Info | Product | Bite alerts never schedule while WeatherKit (the primary provider) is working, and Settings does not say so |

---

## 1. The offline weather cache is unreachable in practice — **High**

**Files:** `Sources/Services/WeatherSnapshots.swift:287-300`, `:124-161`,
`:219-243`; `Sources/Models/WeatherSnapshot.swift:122-127`;
`Sources/Services/NWSWeatherProvider.swift:13`

`CachedWeatherProvider` is the third and last entry in the provider chain
(`Sources/App/BiteCastApp.swift:30`) — the one that is supposed to show
last-known weather when the user is out of signal on the water. It advertises a
24-hour window:

```swift
static let defaultMaxAge: TimeInterval = 24 * 3_600      // WeatherSnapshots.swift:271
```

But the same guard also requires the *origin provider's* expiry to still be in
the future:

```swift
guard maxAge.isFinite, maxAge >= 0, age >= 0, age <= maxAge,
      persisted.provenance.isValid(at: referenceDate) else {   // :294-300
    throw WeatherProviderError.serviceUnavailable
}
```

and `isValid` is a hard `date < expiresAt` (`WeatherSnapshot.swift:126`). The
real expiries are:

- **NWS:** `snapshotLifetime = 30 * 60` — 30 minutes (`NWSWeatherProvider.swift:13`),
  clamped even shorter by an active alert's end date (`:115-118`).
- **WeatherKit:** the provider's own `metadata.expirationDate`, typically ~1 hour.

So `age <= maxAge` can never be the binding constraint: the snapshot is rejected
30–60 minutes after fetch, and the 24-hour `maxAge` is dead code.

It is worse than a dead constant, because the storage layer actively destroys
the file at the same moment. `load(for:)` deletes an expired entry
(`:141-144`), and `purgeInvalidEntries()` — which runs on **every** `save` and
**every** `load` (`:64-65`, `:125-132`) — sweeps every expired entry off disk.
The bytes are gone before the user ever needs them.

Net effect: the cache can only serve a snapshot during the same window in which
`WeatherStore` already holds one in memory. Its single reachable use is a cold
launch, offline, within the provider TTL of the last fetch. **Being offline for
31 minutes is enough to lose the fallback entirely.**

**Why the suite doesn't catch it.** `WeatherProvenance.init` defaults
`expiresAt` to `fetchedAt + 24h` (`WeatherSnapshot.swift:119`), and
`WeatherSnapshotsTests.swift:491-530` builds fixtures that take that default
while passing `maxAge: 24 * 3_600`. The tests therefore exercise a
24 h-expiry/24 h-maxAge pairing that no production provider ever produces.

**Suggested direction.** Decide what "stale but better than nothing" means and
say it in one place. Either (a) let `CachedWeatherProvider` accept an expired
snapshot up to `maxAge` and mark it clearly stale in the UI — it already
re-stamps provenance as `.cache` with `isFallback: true` (`:332-339`), which is
exactly the affordance for this — or (b) drop `maxAge` and be honest that the
cache is a same-TTL cold-launch cache. Whichever way, `purgeInvalidEntries`
must stop deleting on the provider expiry, and a test needs a fixture with a
realistic 30-minute expiry.

---

## 2. The pressure factor is permanently neutral on the NWS path — **High**

**Files:** `Sources/Services/NWSWeatherProvider.swift:347`;
`Sources/Models/ForecastSelection.swift:126-128`, `:147-156`;
`Sources/Models/FishingConditions.swift:61-68`;
`Sources/Services/FishingScorer.swift:221-238`

Barometric trend is the app's headline fishing signal — it carries the largest
non-solunar weight (`FactorWeights.standard.pressure = 0.20`) and its own copy
in the product narrative. On the NWS path it never fires.

`NWSWeatherProvider.hourly(_:)` hard-codes hourly pressure to nil:

```swift
pressureHPa: nil,     // NWSWeatherProvider.swift:347
```

This is deliberate and asserted — `Tests/NWSWeatherProviderTests.swift:160`
expects `first.pressureHPa == nil`. NWS's `/forecast/hourly` genuinely does not
publish a pressure series, so the provider is right not to fabricate one.

The problem is downstream: **both** scoring entry points read pressure *only*
from hourly points and never from the current observation.

```swift
// ForecastSelection.swift:126-128 — history
let pressureHistory = weather.hourly.compactMap { point in
    point.pressureHPa.map { (date: point.date, hPa: $0) }
}
// :147-152 — per-hour reading
let pressure = PressureReading.analyze(
    nowHPa: hour.pressureHPa, history: pressureHistory, now: hour.date, fallback: .steady
)
```

With `hour.pressureHPa == nil`, `PressureReading.analyze` returns early at
`PressureReading.swift:62-68` with `pressure: nil, changePerHour: nil`.
`ForecastSeriesBuilder` then nils out the tendency (`:154-157`), and
`FishingScorer.scorePressure` takes the unavailable branch:

```swift
guard let tendency else {
    return Subscore(raw: 0.5, detail: "Pressure data unavailable")   // FishingScorer.swift:222-224
}
```

Every hour, every species, every NWS-served forecast: a flat 0.5 and the string
"Pressure data unavailable" in the factor breakdown. `FishingConditions.make(snapshot:forecastPoint:calendar:)`
— the overload BiteTime's Fishing Details actually uses — repeats the same
mistake at `FishingConditions.swift:61-68`.

The data is right there and unused. `NWSWeatherProvider.current(_:)` *does*
populate observed station pressure (`:314`, via `barometricPressure` in
hPa), and the **other** `FishingConditions` overload already consults it:

```swift
// FishingConditions.swift:21-25 — the make(snapshot:now:) overload
pressure: PressureReading.analyze(
    currentHPa: snapshot.current.pressureHPa, hourly: snapshot.hourly, now: now
),
```

So the two overloads of the same factory disagree about where pressure comes
from, and the one wired into the live screen is the one that ignores the only
available source.

**Suggested direction.** At minimum, seed `nowHPa` from
`snapshot.current.pressureHPa` for the hour nearest the observation, so the
current hour reports a real tendency instead of "unavailable". A fuller fix
needs a short pressure *history* on the NWS path — persisting each fetch's
observed pressure into a small rolling series would give the 3-hour baseline
`PressureReading.analyze` wants (`PressureReading.swift:74-83`) without inventing
forecast values.

---

## 3. `BiteTimeView.forecastPoints` rebuilds the whole series ~8× per body pass — **Medium**

**Files:** `Sources/Views/BiteTimeView.swift:355-357`, `:359-371`, and its ten
reference sites; `Sources/Services/FishingScorer.swift:207-219`;
`Sources/Models/PressureReading.swift:74-83`

`forecastPoints` is an uncached computed property that runs the entire
`ForecastSeriesBuilder.build(...)` pipeline on access:

```swift
private var forecastPoints: [ForecastPoint] {          // BiteTimeView.swift:359
    guard let snapshot = matchingSnapshot else { return [] }
    ...
    return ForecastSeriesBuilder.build(weather: snapshot, tideSamples: committedTideSamples,
                                       species: species, weights: personalWeights, now: forecastStart)
}
```

It is read ten times in the file (`:375`, `:387`, `:394`, `:437`, `:543`,
`:545`, `:764`, `:770`, `:1095`), and several of those reads chain through
`selectedPoint` → `preferredForecastDate` → `forecastPoints` again. The
`.onChange(of: forecastPoints.map(\.date))` modifier at `:545` guarantees at
least one full rebuild on **every** body evaluation whether or not anything
changed, and `conditions` (`:412`) and `bestBaitContext` (`:422`) each drag in
another. A conservative count is six-plus complete rebuilds per body pass.

Per rebuild, for up to 48 hours:

- **A fresh `DateFormatter` per scored hour.** `FishingScorer.formattedTime`
  constructs one on every call (`FishingScorer.swift:212`), reached whenever an
  active or next window exists (`:175-179`). `DateFormatter` initialization is
  one of the more expensive routine allocations in Foundation; ~48 per rebuild
  × ~6 rebuilds is a few hundred per body pass.
- **`PressureReading.analyze` filters and scans the full hourly array per hour**
  (`PressureReading.swift:75-83`) — O(hours²) over a series that can be 156
  points (NWS) or more.
- Plus `makeDayContexts` running `SolunarCalculator` per context day, and
  `extrema(in:)` over the full tide sample set.

All of it on the main actor. Two things drive re-evaluation independently of
user input: the 60-second `liveNow` ticker (`:521-536`) and any scrub of the
interactive chart.

**Suggested direction.** This is a caching problem, not an algorithmic one.
Hoist the series into `@State` recomputed on a small identity key (snapshot
provenance + species + weights + tide fingerprint + hour bucket) rather than
recomputing per access — the view already has `forecastRevision` and
`tideTaskKey` as the makings of that key. Independently, hoist the
`DateFormatter` in `FishingScorer` to a cached static keyed by
calendar/locale; it is pure overhead as written.

---

## 4. Personalization off-by-one at exactly `minCatches` — **Medium**

**Files:** `Sources/Services/PersonalScoreModel.swift:25-28`, `:42-49`;
`Sources/Services/PersonalInsights.swift:42-45`;
`Sources/Views/FishingView.swift:82-84`, `:128-131`

```swift
let confidence = min(1, Double(sample.count - minCatches) / Double(fullCatches - minCatches))
let shift = maxShift * confidence
guard shift > 0 else { return base }              // PersonalScoreModel.swift:47-49
```

At `sample.count == minCatches` (5), `confidence` is exactly 0, `shift` is 0,
and `weights` returns `.standard` — the score is **not** personalized.

But the reporting helpers cross the threshold at `>=`:

```swift
static func informingSample(_ catches: [CatchEntry], species: Species) -> [CatchEntry] {
    let s = sample(catches, species: species)
    return s.count >= minCatches ? s : []          // :25-28  → returns 5 entries
}
```

So with exactly five qualifying catches:

- `FishingView.tunedCatchCount` is 5 (`FishingView.swift:82-84`), and the hero
  card renders the "tuned to your N catches" affordance (`:128-131`).
- `PersonalInsightsBuilder.build` returns a non-nil insight
  (`PersonalInsights.swift:42-45`) whose `factorChanges` are all `.steady`,
  because it is comparing `.standard` against `.standard`.
- The score itself is the plain studio score.

This directly contradicts the documented contract on
`informingCatchCount`: *"0 means the score is the standard, un-personalized
one."* At five catches it returns 5 and the score is standard.

`Tests/PersonalScoreModelTests.swift` covers 0 (`:34`) and 17 (`:65`); the
boundary is untested.

**Suggested direction.** Pick one threshold and route both the weights and the
badge through it. Either make `informingSample` require `count > minCatches`, or
give the first qualifying catch a non-zero floor of confidence — the latter
probably reads better to a user who just logged their fifth fish and expects
something to happen.

---

## 5. Today's daily forecast is dropped on any evening fetch — **Medium**

**File:** `Sources/Services/NWSWeatherProvider.swift:394-415`

```swift
let groups = Dictionary(grouping: candidates, by: \.date)
return groups.keys.sorted().compactMap { date in
    guard let group = groups[date],
          let daytime = group.first(where: \.isDaytime),
          let nighttime = group.first(where: { !$0.isDaytime })
    else { return nil }                             // :398-402
    ...
}
```

A day survives only if NWS returned **both** its daytime and nighttime period.
NWS `/forecast` returns a rolling list starting at the current period, so for
any fetch after the daytime period closes the first entry is "Tonight"
(`isDaytime: false`) with no matching daytime sibling. That group is dropped and
the 7-day list starts at tomorrow. The tail of the response loses its final day
the same way.

Requiring a nighttime period to have a real low is defensible; silently
dropping the whole day is not the only way to get there.

The astronomy fallback in `ForecastSeriesBuilder.makeDayContexts` happens to
cover the scoring path for *today* specifically
(`ForecastSelection.swift:210-212`, `:235-236` — `day == astronomyDay` falls
back to `weather.astronomy`), so this shows up as a missing row in the daily
list rather than as broken windows. That coincidence is worth not relying on.

**Suggested direction.** Emit the day with a nil `lowCelsius`/`highCelsius` for
the half that is missing and let the UI render a partial row, rather than
`compactMap`-ing the day out of existence.

---

## 6. One malformed hourly period discards the entire forecast — **Medium**

**File:** `Sources/Services/NWSWeatherProvider.swift:155`, `:329-339`

```swift
return try response.properties.periods.map(Self.hourly)     // :155
```

`Self.hourly` throws `WeatherProviderError.decoding` if *any* single period has
an unrecognized `windSpeed` string, an unmapped `windDirection`, or an
unparseable `startTime` (`:330-339`). `windRange` accepts exactly two shapes —
`"N mph"` and `"N to M mph"` (`:539-562`) — so a single period phrased any other
way discards all ~156 hours and forces a chain fallback.

The strictness is inconsistent within the same file: alerts use
`compactMap(Self.alert)` and drop only the bad feature (`:221-222`).

Note that finding 5's daily path throws on the same class of input
(`:368-381`), so a single anomalous daily period kills the forecast too.

**Suggested direction.** `compactMap` the hourly and daily periods and fail only
when the surviving set is empty (the `firstHour` guard at `:82-88` already
handles the empty case). Dropping one hour degrades gracefully; dropping the
provider does not.

---

## 7. `CatchRepository` re-protects every photo on every save — **Medium**

**File:** `Sources/Services/CatchRepository.swift:302-319`, `:394-401`,
`:321-325`

```swift
private func applyCompleteProtectionRecursively(to directory: URL) throws {
    try applyCompleteProtection(to: directory)
    for relativePath in try fileManager.subpathsOfDirectory(atPath: directory.path) {
        try applyCompleteProtection(to: directory.appendingPathComponent(relativePath))  // :396-399
    }
}
```

`subpathsOfDirectory` is a full recursive walk, and each iteration issues a
`setAttributes` syscall. It runs from `prepareStorage()` (`:317`), which is
called by `load()` (`:86`) *and* by `prepareForMutation()` (`:322`) — so
**every add and every remove** re-walks and re-stamps the entire photo library,
plus `protectLegacyRecoveryFiles()` scanning the base directory (`:374-382`).

`CatchRepository` is `@MainActor`, so an angler with a few hundred logged
catches pays O(photos) filesystem syscalls on the main thread every time they
save a fish.

The recursive sweep is the right thing to do once, as a migration. Doing it on
the hot path is the defect.

**Suggested direction.** Gate the recursive sweep behind a persisted
"protection migration completed at version N" marker, and keep only the targeted
`applyCompleteProtection` calls that the transaction itself already performs on
the files it touches.

---

## 8. `TideService.nearestStation` scans 3,000 stations on the main actor — **Medium**

**File:** `Sources/Services/TideService.swift:295-301`

```swift
private func nearestStation(to location: CLLocation) -> TideStation? {
    stations.min { a, b in
        let da = location.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude))
        let db = location.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        return da < db
    }
}
```

Two `CLLocation` allocations and two geodesic `distance(from:)` computations per
comparison, over a catalog the file's own header puts at "~3,000 entries" — so
roughly 6,000 object allocations and 6,000 geodesic solves per call, all on the
main actor.

The irony is that the expensive part was already noticed and moved: `loadStations`
is `nonisolated` with the comment *"Runs off the main actor — the ~1 MB decode
caused a visible hitch"* (`:307`). The scan that consumes that catalog stayed
behind.

**Suggested direction.** Make `nearestStation` a `nonisolated static` over a
`Sendable` array, computing each station's distance once (a squared-degree
prefilter before any geodesic call is more than accurate enough to shortlist,
given the 50-mile cutoff at `:63`).

---

## 9. `Calendar.current` leaks into timezone-threaded logic — **Low**

**Files:** `Sources/Models/FishingConditions.swift:26-30`;
`Sources/Models/Species.swift:175-179`;
`Sources/Services/PersonalScoreModel.swift:138`;
`Sources/Services/PersonalInsights.swift:116`

The codebase is otherwise careful to thread an explicit forecast-zone calendar —
`ForecastSeriesBuilder.forecastCalendar` builds one from
`weather.timeZoneIdentifier` (`ForecastSelection.swift:272-278`), and
`FishingConditions`' second overload documents exactly why:
*"so a selected hour near midnight cannot accidentally inherit today's sun and
moon facts from the device clock"* (`FishingConditions.swift:44-46`).

Four paths bypass it:

```swift
// FishingConditions.swift:26-30 — no `calendar:` argument, so SolunarCalculator defaults to .current
windows: SolunarCalculator.windows(moonrise: astronomy.moonrise, moonset: astronomy.moonset, on: now),
```

```swift
let month = Calendar.current.component(.month, from: date)          // Species.swift:177
let month = Calendar.current.component(.month, from: entry.date)    // PersonalScoreModel.swift:138
switch Calendar.current.component(.hour, from: date) {              // PersonalInsights.swift:116
```

Impact is real but bounded: a catch logged late at night in a different time zone
from the device lands in the wrong month bucket for `seasonAffinity`, and the
"Dawn / Morning / Midday" tally in Your Patterns reflects the device's *current*
zone rather than where the fish was caught. `SolunarCalculator.windows` picking a
device-zone "same day" is the one that could visibly shift a window.

**Suggested direction.** Thread the forecast calendar into all four, matching
the pattern the rest of the scoring path already uses. For `PersonalInsights`
specifically, the catch's own recorded location zone is the correct calendar,
not the device's.

---

## 10. Notification triggers carry no time zone — **Low**

**Files:** `Sources/Services/BiteAlertNotifier.swift:73-78`;
`Sources/Services/BiteWindowNotifier.swift:96-102`

```swift
let components = Calendar.current.dateComponents(
    [.year, .month, .day, .hour, .minute], from: alert.fireDate)
let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
```

`dateComponents` here produces a *wall-clock* description with no `timeZone`
set, so `UNCalendarNotificationTrigger` re-resolves it against whatever the
device's zone is **at fire time**. Two consequences:

- Travel across a time zone between scheduling and firing shifts the
  notification by the offset delta. For an app whose saved spots are explicitly
  places you drive to, this is the normal case rather than an exotic one.
- A `fireDate` that lands inside a DST spring-forward gap matches no wall-clock
  instant, and the notification never fires at all.

The exposure is limited by the short provenance TTL — `allows(fireDate:from:at:)`
already requires `fireDate < provenance.expiresAt`
(`BiteAlertScheduler.swift:30`), so alerts are at most 30–60 minutes out.

**Suggested direction.** Either set `components.timeZone` explicitly from the
forecast zone, or use `UNTimeIntervalNotificationTrigger` — the scheduler
already works in absolute `Date`s and gains nothing from the calendar round-trip.

---

## 11. `PersonalInsights` tie-breaking is non-deterministic — **Low**

**File:** `Sources/Services/PersonalInsights.swift:73-84`, `:127-133`

```swift
return tally.values                                   // :81-84
    .sorted { $0.count > $1.count }
    .prefix(3)
    .map { PersonalInsights.BaitCount(bait: $0.display, count: $0.count) }
```

```swift
guard let best = counts.max(by: { $0.value < $1.value }) else { return nil }   // :131
```

Both iterate a `Dictionary`, whose order is unspecified and varies across
launches because of hash seeding. Neither comparator breaks ties, so two baits
caught the same number of times — extremely common in a small catch log — swap
positions in "Top baits" between app launches, and `topCount` picks an arbitrary
winner among tied conditions.

The type is documented as *"Pure analysis"* (`:3-6`), which this isn't.

**Suggested direction.** Add a deterministic secondary key to both comparators
(alphabetical on the display string is fine, or most-recent-catch if you want it
to feel responsive).

---

## 12. `FishingScore.overall` sums pre-rounded contributions — **Low**

**File:** `Sources/Models/FishingScore.swift:44-47`, `:113-116`

```swift
var contribution: Int { Int((weight * raw * 100).rounded()) }        // :114-116
var overall: Int { max(0, min(100, factors.map(\.contribution).reduce(0, +))) }   // :45-47
```

Each factor is rounded to an integer *before* summing, so the displayed total can
differ from `round(Σ weight·raw·100)` by up to ±2 points with four factors and
±2.5 with five. That is enough to cross a `BiteScoreBand` boundary
(`:26-35`) — a genuine 84.6 can present as 85 "Excellent" or 84 "Strong"
depending on how the individual factors happen to round.

It also means the breakdown a user sees can visibly fail to add up to the headline
number, which is the kind of thing people screenshot.

**Suggested direction.** Compute `overall` from the unrounded weighted sum and
keep `contribution` as a display-only projection. If the per-factor numbers must
add up exactly, use largest-remainder apportionment.

---

## 13. `moonTransit` is fabricated at a day edge — **Low (latent)**

**File:** `Sources/Services/LocalAstronomyProvider.swift:252-273`

```swift
let bestIndex = times.indices.max { altitude(times[lhs]) < altitude(times[rhs]) }!
var lower = times[bestIndex > times.startIndex ? bestIndex - 1 : bestIndex]
var upper = times[bestIndex < times.index(before: times.endIndex) ? bestIndex + 1 : bestIndex]
```

When the true altitude maximum falls outside the sampled day, `bestIndex` lands
on the first or last sample, the bracket collapses to a single instant, the
ternary-search loop never runs, and the function returns that day-edge timestamp
as if it were a transit. `HorizonCrossings` correctly returns `nil` for a rise or
set that doesn't occur in the day (`:181-182`, `:209`); `AltitudeMaximum` has no
equivalent.

This is currently **latent**: `moonTransit` is populated only by
`LocalAstronomyProvider` (`:32`) — `WeatherKitProvider` sets it nil
(`WeatherKitProvider.swift:399`) — and nothing in `Sources/` reads it back. It
becomes a real defect the moment a solunar refinement starts consuming the
field.

**Suggested direction.** Return `nil` when `bestIndex` is at either boundary,
matching the rise/set contract in the same file.

---

## 14. An expiring alert turns a successful fetch into an error — **Low**

**Files:** `Sources/Services/NWSWeatherProvider.swift:93-97`, `:115-118`;
`Sources/Services/WeatherStore.swift:136-140`

`NWSWeatherProvider` clamps snapshot expiry to the earliest still-active alert:

```swift
let earliestAlertExpiry = alertValue.compactMap(\.endDate).filter { $0 > fetchedAt }.min()
...
expiresAt: min(cappedExpiry, earliestAlertExpiry ?? cappedExpiry)
```

If an alert ends a few seconds after `fetchedAt`, the snapshot is born with a
few seconds of life, and `WeatherStore`'s commit-time revalidation rejects it:

```swift
guard result.provenance.isValid(at: now()) else {
    throw WeatherProviderError.serviceUnavailable       // WeatherStore.swift:138-140
}
```

The user sees "Weather is temporarily unavailable" after a fetch that actually
succeeded. It self-heals — the next attempt filters the now-past alert out at
`:95` and gets a full 30-minute expiry — but it is a spurious error state on a
good response.

**Suggested direction.** Floor the alert-derived expiry (e.g. no shorter than a
minute or two), or exclude alerts already inside that floor from the clamp.

---

## 15. Bite alerts never schedule on the primary provider — **Info / product**

**Files:** `Sources/Services/BiteAlertScheduler.swift:6-18`, `:88-90`;
`Sources/Views/SettingsView.swift:13-27`

```swift
static func allows(_ provenance: WeatherProvenance?, at date: Date = .now) -> Bool {
    ...
    return attribution.providerKind == .nationalWeatherService
        && attribution.hasRequiredSecureMetadata          // :16-17
}
```

Weather-derived notifications are permitted **only** when the snapshot came from
NWS. The reasoning is sound and documented at the top of the file: local
notifications can't carry WeatherKit's required combined mark and legal link, so
Apple-derived guidance has to stay inside attributed app UI.

The consequence is that in the normal, healthy case — WeatherKit is first in the
chain (`BiteCastApp.swift:20`) and succeeds — **no bite alert is ever
scheduled**. The feature only works when the primary provider has failed.

Settings gives no hint of this. The toggle reads "Bite alerts" with the footer
*"Get a heads-up before the week's best fishing windows. Alerts refresh each
time you open Plan the Week"* (`SettingsView.swift:26`). A user turns it on,
picks a threshold and a lead time, and nothing arrives — with no way to tell
whether it's broken, whether they mis-set it, or whether it's working as
designed.

This is not a code bug; it's a designed constraint whose user-visible outcome
isn't communicated. Flagging it because "enabled setting that silently does
nothing" is exactly the kind of thing that generates support mail and one-star
reviews.

**Suggested direction.** Surface the state in Settings — when the active
snapshot is WeatherKit-derived, show why alerts are paused. Longer term, the
honest fix is a notification body that carries no Apple-derived weather content
at all (a bare "your next window starts soon — open BiteCast"), which would sit
outside the attribution constraint entirely.

---

## What held up

Worth recording, so the next pass doesn't re-litigate it:

- **Async request identity.** `WeatherStore.load` (`:90-161`) and
  `TideService.load` (`:103-213`) both bump a monotonic `loadID` before
  awaiting and re-check it before every state commit, including the error and
  loading-state paths. Superseded requests can't publish. The commit-time
  revalidation against provider expiry (`WeatherStore.swift:136-140`) correctly
  handles a request that crosses expiry while in flight.
- **Catch-log durability.** `CatchRepository`'s rollback journal is genuinely
  careful: journal removal is the single commit point (`:609-623`), rollback
  distinguishes "this transaction installed the file" from a pre-existing
  collision by testing whether the stage still exists (`:443-455`), directory
  entries are `fsync`'d at each ordering barrier (`:648-663`), and
  `restoreOriginalMetadata` restores exact original bytes rather than
  re-encoding (`:483-496`). Finding 7 is about cost, not correctness.
- **Astronomy math.** `SolarPosition` matches Meeus term-for-term
  (`LocalAstronomyProvider.swift:338-381`), the lunar model is Schlyter's with
  all 12/5/2 perturbation terms intact (`:425-542`), GMST is the standard
  polynomial (`:645-653`), and the topocentric conversion correctly applies WGS-84
  flattening and avoids double-counting parallax in the upper-limb threshold
  (`:110-116`, `:544-582`).
- **URL/redirect hardening.** Every NWS request and every followed redirect is
  re-validated against a canonical host/scheme allowlist
  (`NWSWeatherProvider.swift:624-642`, `:664-686`), including the *final* URL
  after redirection (`:254-258`).
- **Cancellation discipline.** `CancellationError` and `URLError.cancelled` are
  consistently rethrown rather than being converted into user-visible failures,
  at every provider boundary and in the chain (`WeatherProvider.swift:142-145`).

## Recommended order of work

1. Finding 2 (pressure on the NWS path) — largest gap between promised and
   delivered behavior, and the data needed is already in the snapshot.
2. Finding 1 (offline cache) — decide the policy, then make the code and the
   tests agree with it.
3. Finding 3 (series rebuild) — the one users will feel as jank.
4. Findings 5 and 6 together — both are NWS parsing strictness, one diff.
5. Finding 4, then the Low tier.

Findings 7 and 8 are worth doing whenever the surrounding files are next open;
neither is urgent on a small catch log or a single tide lookup, but both scale
badly with real usage.
