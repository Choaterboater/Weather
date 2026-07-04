import Foundation

/// The forward-scoring engine: runs the existing `FishingScorer` across the
/// multi-day forecast to rank the coming week's solunar fishing windows for a
/// location and species. Pure and deterministic given its plain-value inputs.
///
/// Days within the hourly-forecast horizon score with real pressure trend and
/// wind (high confidence); days beyond it fall back to the daily wind with a
/// neutral pressure trend and are marked low confidence.
enum TripPlanner {
    static func outlook(
        days: [DayForecastInput],
        hourly: [HourSample],
        tidesByDay: [Date: [TideEvent]],
        species: Species,
        locationName: String,
        now: Date = .now,
        maxWindows: Int = 12,
        calendar: Calendar = .current
    ) -> WeekOutlook {
        var scored: [ScoredWindow] = []

        for day in days {
            let windows = SolunarCalculator.windows(
                moonrise: day.moonrise, moonset: day.moonset, on: day.date
            )
            let dayKey = calendar.startOfDay(for: day.date)
            let tides = tidesByDay[dayKey] ?? []

            for window in windows where window.end >= now {
                // Score at the window's peak, but never in the past: a window
                // that's active right now (peak already passed) should use the
                // live conditions available at `now`, not fall back to daily.
                let scoreTime = max(window.peak, now)
                let hourlyCond = conditions(at: scoreTime, hourly: hourly)
                let score = FishingScorer.score(
                    moonPhase: day.moonPhase,
                    activeWindow: window,
                    nextWindow: nil,
                    pressureTendency: hourlyCond?.tendency ?? .steady,
                    pressureChangePerHour: hourlyCond?.changePerHour,
                    windMph: hourlyCond?.windMph ?? day.dailyWindMph,
                    species: species,
                    tideEvents: tides,
                    now: scoreTime
                )
                scored.append(ScoredWindow(
                    date: dayKey,
                    start: window.start,
                    end: window.end,
                    score: score.overall,
                    confidence: hourlyCond == nil ? .low : .high,
                    period: window.period,
                    factors: makeFactors(window: window,
                                         tendency: hourlyCond?.tendency,
                                         score: score),
                    species: species
                ))
            }
        }

        scored.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.start < rhs.start
        }

        return WeekOutlook(
            locationName: locationName,
            generatedAt: now,
            windows: Array(scored.prefix(maxWindows))
        )
    }

    /// Wind and pressure trend from the hourly forecast bracketing `date`, or
    /// nil when `date` falls outside the hourly horizon (caller then uses the
    /// daily wind and marks the window low confidence).
    static func conditions(
        at date: Date, hourly: [HourSample]
    ) -> (windMph: Double, tendency: PressureTendency, changePerHour: Double?)? {
        guard let first = hourly.first, let last = hourly.last,
              date >= first.date, date <= last.date else { return nil }

        let nearest = hourly.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        } ?? first

        // Pressure change over the ~3 hours from the window's time.
        let before = hourly.last { $0.date <= date } ?? first
        let after = hourly.first { $0.date >= date.addingTimeInterval(3 * 3600) } ?? last
        let hours = max(1, after.date.timeIntervalSince(before.date) / 3600)
        let changePerHour = (after.pressureHPa - before.pressureHPa) / hours
        let tendency: PressureTendency =
            changePerHour < -0.2 ? .falling : (changePerHour > 0.2 ? .rising : .steady)

        return (nearest.windSpeedMph, tendency, changePerHour)
    }

    /// The window's period plus its most favorable non-solunar driver, as short
    /// human phrases for the row's one-line "why" (e.g. "Major window",
    /// "Falling pressure").
    private static func makeFactors(
        window: BiteWindow, tendency: PressureTendency?, score: FishingScore
    ) -> [String] {
        var result = ["\(window.period.rawValue) window"]

        // Best-contributing non-solunar factor, only if it's genuinely favorable.
        let driver = score.factors
            .filter { $0.kind != .solunar }
            .max { $0.contribution < $1.contribution }
        if let driver, driver.raw >= 0.5 {
            switch driver.kind {
            case .pressure:
                switch tendency {
                case .falling: result.append("Falling pressure")
                case .rising: result.append("Rising pressure")
                default: result.append("Steady pressure")
                }
            case .tide: result.append("Moving tide")
            case .wind: result.append("Good wind")
            case .season: result.append("In season")
            case .solunar: break
            }
        }
        return result
    }
}
