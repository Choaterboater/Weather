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

    func activeWindow(at date: Date = .now) -> BiteWindow? {
        windows.first { $0.isActive(at: date) }
    }

    func nextWindow(after date: Date = .now) -> BiteWindow? {
        windows
            .filter { $0.start > date }
            .min { $0.start < $1.start }
    }
}
