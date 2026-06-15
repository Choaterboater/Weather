# Fishing Weather — Phases 1–2

- **Phase 1 (Weather):** WeatherKit + CoreLocation — current conditions, hourly,
  10-day, and active alerts, styled with Liquid Glass.
- **Phase 2 (Fishing):** a second tab with the deterministic facts layer —
  barometric pressure trend and solunar bite windows (major/minor), plus sun/moon
  times and moon phase. No AI; everything here is calculated.

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
  Views/      RootView.swift               permission gating + load trigger
              MainTabView.swift            Weather / Fishing tabs
              WeatherDashboardView.swift   scrolling composition of sections
              CurrentConditionsView.swift  temp / condition / wind / humidity / UV
              HourlyForecastView.swift      next 24 hours
              DailyForecastView.swift       10-day
              WeatherAlertsView.swift       active alerts
              FishingView.swift            pressure + bite windows + sun/moon
              LocationPromptView.swift      permission + denied states
              GlassCard.swift              reusable Liquid Glass card
  Support/    Info.plist, entitlements, Assets.xcassets
```

## Solunar approximation

Minor windows are centered on moonrise and moonset. Major windows are centered on
the moon's transits (overhead/underfoot), approximated from the rise/set midpoint
and a half-lunar-day (~12h25m) offset — accurate enough for trip planning, and
easy to swap for a precise ephemeris later.

## Next

Phase 3 adds the species picker; Phase 4 the Foundation Models bait engine. See
`../PLAN.md`.
