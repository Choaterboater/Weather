# Fishing Weather — Phase 1 (Weather app)

The plain weather app foundation: WeatherKit + CoreLocation, current conditions,
hourly, 10-day, and active alerts, styled with Liquid Glass.

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
  Views/      RootView.swift               permission gating + load trigger
              WeatherDashboardView.swift   scrolling composition of sections
              CurrentConditionsView.swift  temp / condition / wind / humidity / UV
              HourlyForecastView.swift      next 24 hours
              DailyForecastView.swift       10-day
              WeatherAlertsView.swift       active alerts
              LocationPromptView.swift      permission + denied states
              GlassCard.swift              reusable Liquid Glass card
  Support/    Info.plist, entitlements, Assets.xcassets
```

## Next

Phase 2 adds the fishing conditions layer (pressure trend + solunar bite
windows). See `../PLAN.md`.
