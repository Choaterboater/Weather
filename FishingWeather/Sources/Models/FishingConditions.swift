import Foundation

/// Deterministic fishing facts assembled exclusively from canonical weather.
struct FishingConditions {
    let pressure: PressureReading
    let windows: [BiteWindow]
    let moonPhase: LunarPhase
    let sunrise: Date?
    let sunset: Date?
    let moonrise: Date?
    let moonset: Date?
    let wind: WindSnapshot
    let uvIndex: Int?

    static func make(
        snapshot: WeatherSnapshot,
        now: Date = .now
    ) -> FishingConditions {
        let astronomy = snapshot.astronomy
        return FishingConditions(
            pressure: PressureReading.analyze(
                currentHPa: snapshot.current.pressureHPa,
                hourly: snapshot.hourly,
                now: now
            ),
            windows: SolunarCalculator.windows(
                moonrise: astronomy.moonrise,
                moonset: astronomy.moonset,
                on: now
            ),
            moonPhase: LunarPhase(
                cycleFraction: astronomy.moonPhaseFraction
            ),
            sunrise: astronomy.sunrise,
            sunset: astronomy.sunset,
            moonrise: astronomy.moonrise,
            moonset: astronomy.moonset,
            wind: snapshot.current.wind,
            uvIndex: snapshot.current.uvIndex
        )
    }

    /// Builds the detail facts for the exact hour selected on BiteTime's
    /// shared forecast timeline. The daily astronomy lookup uses the
    /// provider's forecast calendar so a selected hour near midnight cannot
    /// accidentally inherit today's sun and moon facts from the device clock.
    static func make(
        snapshot: WeatherSnapshot,
        forecastPoint: ForecastPoint,
        calendar: Calendar
    ) -> FishingConditions {
        let selectedDayAstronomy = snapshot.daily.first { day in
            calendar.isDate(day.date, inSameDayAs: forecastPoint.date)
        }?.astronomy
        let astronomy = selectedDayAstronomy
            ?? (calendar.isDate(
                snapshot.provenance.fetchedAt,
                inSameDayAs: forecastPoint.date
            ) ? snapshot.astronomy : .empty)
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
            moonPhase: LunarPhase(
                cycleFraction: astronomy.moonPhaseFraction
            ),
            sunrise: astronomy.sunrise,
            sunset: astronomy.sunset,
            moonrise: astronomy.moonrise,
            moonset: astronomy.moonset,
            wind: forecastPoint.weather.wind,
            uvIndex: forecastPoint.weather.uvIndex
        )
    }

    func activeWindow(at date: Date = .now) -> BiteWindow? {
        windows.first { $0.isActive(at: date) }
    }

    func nextWindow(after date: Date = .now) -> BiteWindow? {
        windows
            .filter { $0.start > date }
            .min { $0.start < $1.start }
    }
}
