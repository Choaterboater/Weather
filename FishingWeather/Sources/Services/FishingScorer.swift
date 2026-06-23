import Foundation
import WeatherKit

/// Pure scorer: given today's conditions, the focus species, and (optionally)
/// today's tide events, returns a 0–100 fishing score plus per-factor breakdown.
///
/// The weights are fixed for saltwater (5 factors, tide included). For freshwater
/// the tide weight is redistributed across the remaining factors so the total
/// still sums to 1.0.
enum FishingScorer {

    static func score(
        conditions: FishingConditions,
        species: Species,
        tideEvents: [TideEvent] = [],
        now: Date = .now
    ) -> FishingScore {
        score(
            moonPhase: conditions.moonPhase,
            activeWindow: conditions.activeWindow(at: now),
            nextWindow: conditions.nextWindow(after: now),
            pressureTendency: conditions.pressure.tendency,
            pressureChangePerHour: conditions.pressure.changePerHour,
            windMph: conditions.wind.speed.converted(to: .milesPerHour).value,
            species: species,
            tideEvents: tideEvents,
            now: now
        )
    }

    /// Primitives-based variant used internally by the conditions-taking
    /// overload above, and directly by unit tests (avoids needing to
    /// construct WeatherKit `Wind`/`UVIndex` structs).
    static func score(
        moonPhase: MoonPhase,
        activeWindow: BiteWindow?,
        nextWindow: BiteWindow?,
        pressureTendency: PressureTendency,
        pressureChangePerHour: Double?,
        windMph: Double,
        species: Species,
        tideEvents: [TideEvent] = [],
        now: Date = .now
    ) -> FishingScore {
        let waterType = species.waterType ?? .freshwater
        let includesTide = !tideEvents.isEmpty && waterType != .freshwater

        // Base weights (must sum to 1.0).
        var w_solunar = 0.25
        var w_pressure = 0.20
        var w_wind = 0.15
        var w_tide = 0.25
        var w_season = 0.15

        if !includesTide {
            // Redistribute the tide share across the remaining factors.
            let bonus = w_tide / 4
            w_solunar += bonus
            w_pressure += bonus
            w_wind += bonus
            w_season += bonus
            w_tide = 0
        }

        let solunar = scoreSolunar(moonPhase: moonPhase, activeWindow: activeWindow, nextWindow: nextWindow, now: now)
        let pressure = scorePressure(tendency: pressureTendency, changePerHour: pressureChangePerHour)
        let wind = scoreWind(mph: windMph)
        let season = scoreSeason(species: species, now: now)

        var factors: [ScoreFactor] = [
            ScoreFactor(kind: .solunar, label: "Solunar", weight: w_solunar, raw: solunar.raw, detail: solunar.detail),
            ScoreFactor(kind: .pressure, label: "Pressure", weight: w_pressure, raw: pressure.raw, detail: pressure.detail),
            ScoreFactor(kind: .wind, label: "Wind", weight: w_wind, raw: wind.raw, detail: wind.detail),
            ScoreFactor(kind: .season, label: "Season", weight: w_season, raw: season.raw, detail: season.detail)
        ]

        if includesTide {
            let tide = scoreTide(events: tideEvents, now: now)
            factors.insert(
                ScoreFactor(kind: .tide, label: "Tide", weight: w_tide, raw: tide.raw, detail: tide.detail),
                at: 3
            )
        }

        return FishingScore(factors: factors)
    }

    // MARK: - Per-factor scoring

    private static func scoreSolunar(moonPhase: MoonPhase, activeWindow: BiteWindow?, nextWindow: BiteWindow?, now: Date) -> Subscore {
        let phaseScore: Double
        switch moonPhase {
        case .new, .full: phaseScore = 1.0
        case .waxingGibbous, .waningGibbous, .waxingCrescent, .waningCrescent: phaseScore = 0.7
        case .firstQuarter, .lastQuarter: phaseScore = 0.5
        @unknown default: phaseScore = 0.6
        }

        let windowScore: Double
        let windowDetail: String
        if let active = activeWindow {
            if active.period == .major {
                windowScore = 1.0
                windowDetail = "Major bite window active until \(active.end.formatted(date: .omitted, time: .shortened))"
            } else {
                windowScore = 0.8
                windowDetail = "Minor bite window active until \(active.end.formatted(date: .omitted, time: .shortened))"
            }
        } else if let next = nextWindow {
            let minutes = next.peak.timeIntervalSince(now) / 60
            if minutes < 60 {
                windowScore = 0.7
                windowDetail = "Next window in \(Int(minutes)) min (\(next.period.rawValue.lowercased()))"
            } else if minutes < 180 {
                windowScore = 0.5
                windowDetail = "Next window in \(Int(minutes / 60)) hr"
            } else {
                windowScore = 0.3
                windowDetail = "No nearby bite window"
            }
        } else {
            windowScore = 0.4
            windowDetail = "No solunar windows today"
        }

        let raw = 0.4 * phaseScore + 0.6 * windowScore
        let detail = "\(moonPhase.displayName) — \(windowDetail)"
        return Subscore(raw: raw, detail: detail)
    }

    private static func scorePressure(tendency: PressureTendency, changePerHour: Double?) -> Subscore {
        let base: Double
        switch tendency {
        case .falling: base = 1.0
        case .steady:  base = 0.65
        case .rising:  base = 0.45
        }
        // Magnitude boosts confidence — a fast-falling barometer ahead of a
        // front is the textbook trigger.
        let magnitude = abs(changePerHour ?? 0)
        let boost = min(0.2, magnitude / 5)
        let raw = tendency == .falling ? min(1.0, base + boost) : base
        return Subscore(raw: raw, detail: "\(tendency.label) — \(tendency.fishingNote)")
    }

    private static func scoreWind(mph: Double) -> Subscore {
        let raw: Double
        let note: String
        switch mph {
        case ..<2:
            raw = 0.55; note = "Glassy — fish can be spooky."
        case 2..<6:
            raw = 0.85; note = "Light chop — good visibility under the surface."
        case 6..<13:
            raw = 1.0; note = "Ideal chop — moving water on the surface."
        case 13..<19:
            raw = 0.65; note = "Breezy — tougher casting; fish lee shores."
        case 19..<25:
            raw = 0.4; note = "Strong wind — limited spot selection."
        default:
            raw = 0.2; note = "Heavy wind — stay safe, watch the forecast."
        }
        return Subscore(raw: raw, detail: "\(Int(mph)) mph — \(note)")
    }

    private static func scoreTide(events: [TideEvent], now: Date) -> Subscore {
        guard !events.isEmpty else {
            return Subscore(raw: 0.5, detail: "No tide data available.")
        }
        // Find minutes to the nearest hi or low.
        let nearest = events
            .map { abs($0.time.timeIntervalSince(now)) / 60 }
            .min() ?? 360
        let raw: Double
        let label: String
        switch nearest {
        case ..<20:
            raw = 0.5; label = "Slack water at the turn — bite often pauses."
        case 20..<60:
            raw = 0.85; label = "Tide just turning — moving water building."
        case 60..<180:
            raw = 1.0; label = "Strong moving water — prime tide."
        case 180..<240:
            raw = 0.7; label = "Tide easing — still fishable."
        default:
            raw = 0.5; label = "Off-peak tide phase."
        }
        return Subscore(raw: raw, detail: label)
    }

    private static func scoreSeason(species: Species, now: Date) -> Subscore {
        let month = Calendar.current.component(.month, from: now)
        let peaks = peakMonths(for: species)
        if peaks.isEmpty {
            return Subscore(raw: 0.7, detail: "Available year-round.")
        }
        if peaks.contains(month) {
            return Subscore(raw: 1.0, detail: "In peak season for \(species.displayName.lowercased()).")
        }
        // Adjacent month? Use circular distance to nearest peak month.
        let distance = peaks.map { circularMonthDistance($0, month) }.min() ?? 6
        switch distance {
        case 1: return Subscore(raw: 0.7, detail: "Shoulder month for \(species.displayName.lowercased()).")
        case 2: return Subscore(raw: 0.55, detail: "Off-peak but catchable.")
        default: return Subscore(raw: 0.35, detail: "Out of season for \(species.displayName.lowercased()).")
        }
    }

    private static func circularMonthDistance(_ a: Int, _ b: Int) -> Int {
        let d = abs(a - b)
        return min(d, 12 - d)
    }

    /// Rough peak feeding/availability months per species. Empty array means
    /// "year-round; no strong seasonal bias".
    private static func peakMonths(for species: Species) -> Set<Int> {
        switch species {
        case .all: []
        case .bass: [3, 4, 5, 6, 9, 10, 11]
        case .crappie: [2, 3, 4, 5]
        case .catfish: [5, 6, 7, 8, 9]
        case .bluegill: [5, 6, 7, 8]
        case .redfish: [9, 10, 11]
        case .speckledTrout: [3, 4, 5, 10, 11]
        case .pompano: [3, 4, 5, 6, 10, 11]
        case .flounder: [9, 10, 11]
        case .sheepshead: [2, 3, 4]
        case .snook: [4, 5, 6, 7, 8, 9]
        case .mangroveSnapper: [5, 6, 7, 8, 9]
        }
    }

    private struct Subscore {
        let raw: Double
        let detail: String
    }
}
