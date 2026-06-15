# Fishing Weather — Phases 1–5

- **Phase 1 (Weather):** WeatherKit + CoreLocation — current conditions, hourly,
  10-day, and active alerts, styled with Liquid Glass.
- **Phase 2 (Fishing):** a second tab with the deterministic facts layer —
  barometric pressure trend and solunar bite windows (major/minor), plus sun/moon
  times and moon phase. No AI; everything here is calculated.
- **Phase 3 (Species):** a tap-to-pick species row at the top of the Fishing tab
  (All / Bass / Crappie / Catfish / Bluegill), persisted via `@AppStorage`, with a
  static focus note per species. The selection is what Phase 4's AI keys off.
- **Phase 4 (AI bait engine):** Foundation Models with structured `@Generable`
  output — a bait card (top bait, color, technique, depth, confidence, why),
  a plain-language daily report, and an ask-anything box. Replicate generates lure
  art for the card (optional; disabled without a token).
- **Phase 5 (Polish):** saved fishing spots (a Spots tab to save/switch between
  locations, persisted) and a local notification 30 minutes before the next bite
  window.

Targets **iOS 27 / Xcode 27 / Swift 6.4** (strict concurrency).

## Generate the Xcode project

The repo stores source + an [XcodeGen](https://github.com/yonaskolb/XcodeGen)
spec (`project.yml`) instead of a committed `.xcodeproj`, so the project file
never causes merge conflicts.

```bash
brew install xcodegen      # once
cd FishingWeather
xcodegen generate          # creates FishingWeather.xcodeproj
open FishingWeather.xcodeproj
```

> Prefer not to use XcodeGen? Create a new iOS App in Xcode, then drag the
> `Sources/` folder in. The layout maps 1:1 to the spec.

## Before it runs

1. **Signing team.** In Xcode → target → Signing & Capabilities, pick your team
   (or set `DEVELOPMENT_TEAM` in `project.yml`). The bundle id placeholder is
   `com.example.fishingweather` — change it to your own.
2. **WeatherKit.** Requires a paid Apple Developer account. The
   `com.apple.developer.weatherkit` entitlement is already in
   `Sources/Support/FishingWeather.entitlements`; also enable the **WeatherKit**
   service for your App ID in the developer portal.
3. **Location.** `NSLocationWhenInUseUsageDescription` is set in `Info.plist`.

## Layout

```
Sources/
  App/        FishingWeatherApp.swift      app entry, injects observables
  Services/   LocationManager.swift        CoreLocation wrapper (@Observable)
              WeatherStore.swift           WeatherKit fetch + state
  Models/     BiteWindow.swift             solunar window value type
              PressureReading.swift        pressure + trend analysis
              SolunarCalculator.swift      major/minor windows from moon rise/set
              MoonPhase+Display.swift      phase name / symbol / bite rating
              FishingConditions.swift      assembles the facts from WeatherKit
              Species.swift                species enum + tint + focus note
              BaitRecommendation.swift     @Generable structured AI output
              FishingSpot.swift            saved-spot value type
  Services/   …                            (also) BaitEngine.swift, AppSecrets.swift,
                                           ReplicateClient.swift, SpotStore.swift,
                                           BiteWindowNotifier.swift
  Views/      RootView.swift               permission gating + load trigger
              MainTabView.swift            Weather / Fishing tabs
              SpeciesPicker.swift          tap-to-pick species row
              WeatherDashboardView.swift   scrolling composition of sections
              CurrentConditionsView.swift  temp / condition / wind / humidity / UV
              HourlyForecastView.swift      next 24 hours
              DailyForecastView.swift       10-day
              WeatherAlertsView.swift       active alerts
              FishingView.swift            species + AI + pressure + windows + sun/moon
              BaitEngineView.swift         AI bait card, report, ask-anything box
              BaitArtView.swift            Replicate lure art (optional)
              SpotsView.swift              save / switch saved fishing spots
              LocationPromptView.swift      permission + denied states
              GlassCard.swift              reusable Liquid Glass card
  Support/    Info.plist, entitlements, Assets.xcassets
```

## AI & image generation

- **Foundation Models** runs on-device; no entitlement needed, but the user must
  have Apple Intelligence enabled. When unavailable, the AI section explains why
  and the deterministic facts (Phase 2/3) still work.
- **Replicate** is optional. Copy `Secrets.xcconfig.example` to `Secrets.xcconfig`
  (gitignored) and set `REPLICATE_API_TOKEN`, or export it as an env var. Without
  a token, lure-art generation is silently skipped.

## Solunar approximation

Minor windows are centered on moonrise and moonset. Major windows are centered on
the moon's transits (overhead/underfoot), approximated from the rise/set midpoint
and a half-lunar-day (~12h25m) offset — accurate enough for trip planning, and
easy to swap for a precise ephemeris later.

## Status

Phases 1–5 are scaffolded. Remaining work is a real build pass on a Mac with
Xcode 27 (this repo was assembled on Linux and hasn't been compiled), signing,
WeatherKit enablement, and an optional Replicate token. See `../PLAN.md`.
