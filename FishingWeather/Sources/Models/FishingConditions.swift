import Foundation
import WeatherKit

/// The deterministic fishing facts for the current location and day, assembled
/// from WeatherKit data. No AI — pressure trend and solunar windows are computed.
struct FishingConditions {
    let pressure: PressureReading
    let windows: [BiteWindow]
    let moonPhase: MoonPhase
    let sunrise: Date?
    let sunset: Date?
    let moonrise: Date?
    let moonset: Date?
    let wind: Wind
    let uvIndex: UVIndex

    static func make(
        current: CurrentWeather,
        hourly: Forecast<HourWeather>,
        today: DayWeather,
        now: Date = .now
    ) -> FishingConditions {
        FishingConditions(
            pressure: PressureReading.analyze(current: current, hourly: hourly.forecast, now: now),
            windows: SolunarCalculator.windows(
                moonrise: today.moon.moonrise,
                moonset: today.moon.moonset,
                on: now
            ),
            moonPhase: today.moon.phase,
            sunrise: today.sun.sunrise,
            sunset: today.sun.sunset,
            moonrise: today.moon.moonrise,
            moonset: today.moon.moonset,
            wind: current.wind,
            uvIndex: current.uvIndex
        )
    }

    /// A window happening right now, if any.
    func activeWindow(at date: Date = .now) -> BiteWindow? {
        windows.first { $0.isActive(at: date) }
    }

    /// The next window that hasn't started yet.
    func nextWindow(after date: Date = .now) -> BiteWindow? {
        windows
            .filter { $0.start > date }
            .min { $0.start < $1.start }
    }
}
