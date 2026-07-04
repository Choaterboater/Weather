import Foundation
import WeatherKit

/// Pure scorer: given today's conditions, the focus species, and (optionally)
/// today's tide events, returns a 0–100 fishing score plus per-factor breakdown.
///
/// The weights are fixed for saltwater (5 factors, tide included). For freshwater
/// the tide weight is redistributed across the remaining factors so the total
/// still sums to 1.0.
enum FishingScorer {

    // MARK: - Tunable parameters

    /// Weighting between phase vs. window proximity in the solunar factor.
    private static let solunarPhaseWeight: Double = 0.4
    private static let solunarWindowWeight: Double = 0.6

    /// Bias applied to proximity for major/minor windows.
    private static let majorWindowBias: Double = 1.0
    private static let minorWindowBias: Double = 0.85

    /// Half-width (mph) around key thresholds where we blend wind scores to avoid cliffs.
    private static let windThresholdHalfWidth: Double = 0.5

    /// Maximum boost applied to the tide factor based on daily range (ft),
    /// and the normalization divisor that maps typical ranges to small boosts.
    private static let tideBoostCap: Double = 0.08
    private static let tideBoostNormalization: Double = 10.0

    static func score(
        conditions: FishingConditions,
        species: Species,
        tideEvents: [TideEvent] = [],
        weights: FactorWeights = .standard,
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
            weights: weights,
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
        weights: FactorWeights = .standard,
        now: Date = .now
    ) -> FishingScore {
        // `.all` has no water type — include tide whenever events were supplied
        // (caller already gated on saltwater/brackish spots). Only an explicit
        // freshwater species drops the tide factor.
        let includesTide = !tideEvents.isEmpty && species.waterType != .freshwater

        // Factor weights (must sum to 1.0) — standard, or personalized.
        var w_solunar = weights.solunar
        var w_pressure = weights.pressure
        var w_wind = weights.wind
        var w_tide = weights.tide
        var w_season = weights.season

        if !includesTide {
            // Redistribute the tide share across the remaining factors.
            let bonus = w_tide / 4
            w_solunar += bonus
            w_pressure += bonus
            w_wind += bonus
            w_season += bonus
            w_tide = 0
        }

        #if DEBUG
        let __sum = w_solunar + w_pressure + w_wind + w_tide + w_season
        assert(abs(__sum - 1.0) < 0.0001, "FishingScorer: weights must sum to 1.0 (got \(__sum))")
        #endif

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

    /// Smooth proximity to a bite window's peak, normalized to [0, 1].
    /// Uses a cosine falloff across roughly two half-durations around peak,
    /// and biases major windows slightly higher than minor.
    private static func solunarProximity(window: BiteWindow, now: Date) -> Double {
        let half = window.period.duration / 2
        let dist = abs(window.peak.timeIntervalSince(now))
        // Map distance to [0, 1] where 1 is at peak, 0 is far from it.
        let x = max(0.0, 1.0 - dist / (2.0 * half))
        // Cosine smoothing: 1 at peak, ~0 at the edge of the support.
        let base = 0.5 * (1.0 + cos((1.0 - x) * .pi))
        let bias = (window.period == .major) ? Self.majorWindowBias : Self.minorWindowBias
        return min(1.0, max(0.0, base * bias))
    }

    private static func scoreSolunar(
        moonPhase: MoonPhase,
        activeWindow: BiteWindow?,
        nextWindow: BiteWindow?,
        now: Date
    ) -> Subscore {
        // Phase contribution: coarse but stable.
        let phaseScore: Double
        switch moonPhase {
        case .new, .full: phaseScore = 1.0
        case .waxingGibbous, .waningGibbous, .waxingCrescent, .waningCrescent: phaseScore = 0.7
        case .firstQuarter, .lastQuarter: phaseScore = 0.5
        @unknown default: phaseScore = 0.6
        }

        // Window proximity contribution: smooth falloff around peak.
        let windowScore: Double
        let windowDetail: String
        if let active = activeWindow {
            windowScore = solunarProximity(window: active, now: now)
            if active.period == .major {
                windowDetail = "Major bite window active until \(active.end.formatted(date: .omitted, time: .shortened))"
            } else {
                windowDetail = "Minor bite window active until \(active.end.formatted(date: .omitted, time: .shortened))"
            }
        } else if let next = nextWindow {
            windowScore = solunarProximity(window: next, now: now)
            let minutes = Int(max(0, next.peak.timeIntervalSince(now) / 60))
            if minutes < 60 {
                windowDetail = "Next window in \(minutes) min (\(next.period.rawValue.lowercased()))"
            } else if minutes < 180 {
                windowDetail = "Next window in \(minutes / 60) hr"
            } else {
                windowDetail = "No nearby bite window"
            }
        } else {
            // No windows available today — keep a neutral-ish baseline.
            windowScore = 0.4
            windowDetail = "No solunar windows today"
        }

        let raw = Self.solunarPhaseWeight * phaseScore + Self.solunarWindowWeight * windowScore
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
        // Base piecewise values
        let base: Double
        let note: String
        switch mph {
        case ..<2:
            base = 0.55; note = "Glassy — fish can be spooky."
        case 2..<6:
            base = 0.85; note = "Light chop — good visibility under the surface."
        case 6..<13:
            base = 1.0; note = "Ideal chop — moving water on the surface."
        case 13..<19:
            base = 0.65; note = "Breezy — tougher casting; fish lee shores."
        case 19..<25:
            base = 0.4; note = "Strong wind — limited spot selection."
        default:
            base = 0.2; note = "Heavy wind — stay safe, watch the forecast."
        }

        // Smooth transitions near key thresholds to avoid cliffs.
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * min(max(t, 0), 1) }
        var raw = base
        let halfWidth = Self.windThresholdHalfWidth

        // 2 mph threshold: 0.55 -> 0.85
        if abs(mph - 2.0) <= halfWidth {
            let t = (mph - (2.0 - halfWidth)) / (2 * halfWidth)
            raw = lerp(0.55, 0.85, t)
        }

        // 6 mph threshold: 0.85 -> 1.0
        if abs(mph - 6.0) <= halfWidth {
            let t = (mph - (6.0 - halfWidth)) / (2 * halfWidth)
            raw = lerp(0.85, 1.0, t)
        }

        // 13 mph threshold: 1.0 -> 0.65
        if abs(mph - 13.0) <= halfWidth {
            let t = (mph - (13.0 - halfWidth)) / (2 * halfWidth)
            raw = lerp(1.0, 0.65, t)
        }

        // 19 mph threshold: 0.65 -> 0.40
        if abs(mph - 19.0) <= halfWidth {
            let t = (mph - (19.0 - halfWidth)) / (2 * halfWidth)
            raw = lerp(0.65, 0.40, t)
        }

        // 25 mph threshold: 0.40 -> 0.20
        if abs(mph - 25.0) <= halfWidth {
            let t = (mph - (25.0 - halfWidth)) / (2 * halfWidth)
            raw = lerp(0.40, 0.20, t)
        }

        return Subscore(raw: raw, detail: "\(Int(mph)) mph — \(note)")
    }

    private static func scoreTide(events: [TideEvent], now: Date) -> Subscore {
        guard !events.isEmpty else {
            return Subscore(raw: 0.5, detail: "No tide data available.")
        }
        // Find minutes offset to the nearest hi or low (negative = past, positive = future).
        let offsets = events.map { $0.time.timeIntervalSince(now) / 60 }
        let nearestOffset = offsets.min(by: { abs($0) < abs($1) }) ?? 0
        let nearest = abs(nearestOffset)
        var raw: Double
        var label: String
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

        // Small boost based on the day's tide range, when heights are available.
        let heights = events.compactMap { $0.heightFeet }
        if heights.count >= 2, let minH = heights.min(), let maxH = heights.max() {
            let range = maxH - minH
            let boost = min(Self.tideBoostCap, max(0.0, range / Self.tideBoostNormalization))
            raw = min(1.0, raw + boost)
        }

        // Add timing hint for the nearest tide.
        let suffix: String = {
            let minutes = Int(nearest.rounded())
            if nearest < 60 {
                return nearestOffset >= 0 ? "Next tide in \(minutes) min" : "Last tide \(minutes) min ago"
            } else {
                let hours = Int((nearest / 60).rounded())
                return nearestOffset >= 0 ? "Next tide in \(hours) hr" : "Last tide \(hours) hr ago"
            }
        }()
        return Subscore(raw: raw, detail: "\(label) — \(suffix)")
    }

    private static func scoreSeason(species: Species, now: Date) -> Subscore {
        let month = Calendar.current.component(.month, from: now)
        let peaks = species.peakMonths
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

    private struct Subscore {
        let raw: Double
        let detail: String
    }
    
    #if DEBUG
    /// Human-readable factor breakdown for quick tuning in debug builds.
    static func debugDescribe(
        moonPhase: MoonPhase,
        activeWindow: BiteWindow?,
        nextWindow: BiteWindow?,
        pressureTendency: PressureTendency,
        pressureChangePerHour: Double?,
        windMph: Double,
        species: Species,
        tideEvents: [TideEvent] = [],
        now: Date = .now
    ) -> String {
        let score = score(
            moonPhase: moonPhase,
            activeWindow: activeWindow,
            nextWindow: nextWindow,
            pressureTendency: pressureTendency,
            pressureChangePerHour: pressureChangePerHour,
            windMph: windMph,
            species: species,
            tideEvents: tideEvents,
            now: now
        )
        let lines = score.factors.map { f in
            "\(f.label): raw=\(Int((f.raw * 100).rounded()))% · weight=\(Int((f.weight * 100).rounded()))% → +\(f.contribution) — \(f.detail)"
        }
        return lines.joined(separator: "\n")
    }
    #endif
}
