# Weekly Trip Planner — Design

- **Date:** 2026-07-03
- **Status:** Approved (brainstorm), ready for implementation plan
- **Feature 1 of 4** in the roadmap (trip planner → smart alerts → widget → catch-log insights). This feature builds the reusable *forward-scoring* engine that Smart Alerts and the Widget will later share.

## Summary

Anglers currently see a fishing score only for *now*. The Weekly Trip Planner answers "**when this week should I go?**" by running the existing `FishingScorer` across the multi-day forecast and presenting a **ranked list of the week's best fishing windows** for the active location.

## User goal

> Pick my active spot, see the best day + time windows to fish over the coming week, ranked, with a plain-language "why" and an honest confidence flag on the days that are further out.

## Decisions locked in brainstorming

1. **Horizon:** score the **full 7 days**, but mark confidence. Days ~1–3 (within the hourly forecast horizon) are **high** confidence; days ~4–7 (daily forecast only, no hourly pressure trend) are **low** confidence, visibly flagged.
2. **Presentation:** a **ranked window list** (top score first), each row showing day + time range, a score bar, a confidence dot, and a one-line "why".
3. **Placement:** reached from the **Fishing tab** (a "Plan the Week" entry that pushes `TripPlannerView`). No new tab — six already exist and the planner is squarely "when to fish."
4. **Fetching:** the planner performs its **own on-demand forecast fetch** when opened, leaving the dashboard's lean ±26h fetch unchanged.

## Goals

- Rank the coming week's fishing windows for the active spot / current location.
- Reuse `FishingScorer` and `SolunarCalculator` — no parallel scoring logic.
- Be honest about forecast confidence rather than implying uniform accuracy.
- Produce a pure, testable "score the forecast forward in time" engine reusable by later features.

## Non-goals

- No push notifications (that is the Smart Alerts feature, #2).
- No home-screen surface (that is the Widget, #3).
- No trip journaling / booking. Read-only planning.
- No per-window map or deep navigation in v1 (rows are informational; a future "jump to this day" is noted below).

## Placement & navigation

`FishingView` gains a compact entry at the top of its stack — a `GlassCard` "Plan the Week" link (calendar icon + subtitle) wrapped in a `NavigationLink` — that pushes `TripPlannerView` onto the existing Fishing `NavigationStack`. The planner inherits the active location the rest of the app uses: `spots.selectedSpot?.location ?? location.location`.

## Data model (`Sources/Models`)

```
struct ScoredWindow: Identifiable {
    let id: UUID
    let date: Date          // the window's day (start-of-day for grouping)
    let start: Date
    let end: Date
    let score: Int          // 0–100, from FishingScore
    let confidence: Confidence   // .high | .low
    let period: BitePeriod       // .major | .minor — the solunar window this row is
    let factors: [String]        // top ~2 reasons, e.g. ["Major window", "Falling pressure", "Dawn"]
    let species: Species
    enum Confidence { case high, low }
}

struct WeekOutlook {
    let locationName: String
    let generatedAt: Date
    let windows: [ScoredWindow]  // sorted by score descending, capped (~12)
}
```

A scored window **is** a solunar window, so `period` reuses the existing `BitePeriod` enum (`.major` / `.minor`). Dawn/dusk is not a window type — it is a time-of-day scoring bonus that surfaces in `factors` (e.g. "Dawn") when a window overlaps the day's sunrise/sunset.

## Engine — `TripPlanner` (`Sources/Services`, pure)

Signature (illustrative):

```
enum TripPlanner {
    static func outlook(
        days: [DayForecastInput],     // one per forecast day (moon rise/set, sun times, daily wind/condition, uv)
        hourly: [HourSample],         // extended hourly samples (pressure, wind, temp) as far as WeatherKit gives
        tidesByDay: [Date: [TideEvent]],
        species: Species,
        now: Date
    ) -> WeekOutlook
}
```

Algorithm, per forecast day:
1. Compute the day's solunar windows with `SolunarCalculator.windows(moonrise:moonset:on:)`.
2. For each window, assemble a `FishingConditions` snapshot for that window's time:
   - **Pressure:** trend computed from the `hourly` samples bracketing the window — only when the window falls within the hourly horizon; otherwise neutral/omitted.
   - **Solunar windows:** that day's computed windows.
   - **Tides:** `tidesByDay` for the day (empty for inland/freshwater — scorer already tolerates this).
   - **Wind / weather / sun / moon:** from the hourly sample if available, else the daily forecast entry.
3. Score the snapshot with `FishingScorer.score(conditions:species:tideEvents:)`.
4. `confidence = .high` if the hourly forecast covered the window, else `.low`.
5. `factors` = top contributors pulled from the returned `FishingScore` breakdown.

Then flatten all windows across all days, sort by `score` descending, and cap at ~12. Ties broken by soonest start.

**Reuse note:** the engine constructs `FishingConditions` for arbitrary future times from forecast components (WeatherKit `DayWeather`/`HourWeather` are the inputs behind `DayForecastInput`/`HourSample`). This is the single new capability; scoring itself is unchanged.

## Forecast fetching — `TripForecastLoader` (`Sources/Services`)

On `TripPlannerView` appear (keyed by active location), load and cache for the session:
- WeatherKit **hourly** as far out as it provides (request a wide window, e.g. up to ~10 days; availability defines the high-confidence horizon).
- WeatherKit **daily** (10-day) for moon/sun/daily conditions across the week.
- **A week of NOAA tide predictions** — extend `TideService` with a date-range predictions call (NOAA supports `begin_date`/`end_date`); inland locations yield none.

This is deliberately separate from `WeatherStore`'s dashboard fetch so the everyday load stays lean. Cache is invalidated on location change (same key strategy as the rest of the app).

## UI — `TripPlannerView` + `ScoredWindowRow`

- Ranked list of `ScoredWindow` rows in Liquid Glass (`GlassCardStack`), each row: weekday + time range, a score bar (tinted by score like `FishingScoreCard`), a filled/hollow confidence dot with a "High/Low" tag, and the `factors` "why" line.
- Header: location name + a one-line confidence legend.
- Focused on the active species from the shared `@AppStorage("selectedSpecies")` picker.
- States mirror the rest of the app: no-location prompt, loading spinner, error card with Retry, and an empty state ("No strong windows this week — conditions are flat").

## Error handling & edge cases

- **No location:** show the standard "waiting for location" / prompt, no fetch.
- **Forecast fetch fails:** error card + Retry (WeatherKit failure is also why this can't be verified on the simulator; the on-device path is what matters).
- **Inland / no tides:** score without tides (already supported).
- **A day missing moon data:** contributes a weather-only window or is skipped — never crashes.
- **All-low week:** still render the ranked list; empty only if literally no windows computed.

## Testing

- `TripPlannerTests` (pure, Swift Testing) with synthetic forecast fixtures:
  - windows are sorted by score descending and capped at the top N;
  - a window beyond the hourly horizon is marked `.low`, one within is `.high`;
  - a day with no moon data does not crash and yields no bogus window;
  - inland input (no tides) still scores;
  - tie-break prefers the sooner window.
- `FishingScorer` and `SolunarCalculator` are already unit-tested; the planner tests focus on week assembly, ranking, and confidence.

## Rough build sequence

1. `ScoredWindow` / `WeekOutlook` models.
2. `TripPlanner` engine + `TripPlannerTests` (TDD against fixtures).
3. `TripForecastLoader` + `TideService` date-range predictions.
4. `TripPlannerView` + row, wired into `FishingView` via a "Plan the Week" link.
5. Verify on device / via a mock-data harness (WeatherKit can't run on the simulator).

## Future (out of scope here, enabled by this)

- Tapping a window jumps to that day's full breakdown.
- Smart Alerts (#2) schedules notifications for the top upcoming high-confidence windows via this same engine.
- The Widget (#3) surfaces the single next best window from a shared snapshot.
