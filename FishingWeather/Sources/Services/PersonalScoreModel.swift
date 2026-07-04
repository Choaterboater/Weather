import Foundation

/// The "learns your catches" personalization: derives tuned `FactorWeights`
/// from a user's catch log so the Fishing Score leans on whatever conditions
/// actually produce fish *for them*. Pure and deterministic.
///
/// A factor's weight scales by its **affinity relative to the mean of the
/// measured affinities**, raised to a confidence-scaled power. Two consequences
/// make this safe: a uniform pattern (all factors equally favorable when you
/// catch) cancels under renormalization, so it never inflates the score; and
/// factors we can't yet measure (wind/tide aren't in the catch snapshot) sit at
/// the reference and keep their standard weight instead of being trimmed.
enum PersonalScoreModel {
    /// Catches needed before any personalization applies.
    static let minCatches = 5
    /// Catches at which personalization reaches full strength.
    static let fullCatches = 15
    /// Maximum weighting shift, at full confidence.
    static let maxShift = 0.5

    /// The catches that actually inform personalization — the per-species sample
    /// (or the fallback), but only once it clears `minCatches`. Empty otherwise.
    /// Shared by the scorer and the "Your Patterns" analysis so they can't
    /// disagree about which catches count.
    static func informingSample(_ catches: [CatchEntry], species: Species) -> [CatchEntry] {
        let s = sample(catches, species: species)
        return s.count >= minCatches ? s : []
    }

    /// How many catches informed the weights, for the "tuned to your N catches"
    /// badge. 0 means the score is the standard, un-personalized one.
    static func informingCatchCount(_ catches: [CatchEntry], species: Species) -> Int {
        informingSample(catches, species: species).count
    }

    /// Catches counting toward personalization, even before the threshold — for
    /// the "Learning · N/5" progress hint. Reaches `minCatches` when tuning begins.
    static func sampleCount(_ catches: [CatchEntry], species: Species) -> Int {
        sample(catches, species: species).count
    }

    static func weights(from catches: [CatchEntry], species: Species,
                        base: FactorWeights = .standard) -> FactorWeights {
        let sample = sample(catches, species: species)
        guard sample.count >= minCatches else { return base }

        let confidence = min(1, Double(sample.count - minCatches) / Double(fullCatches - minCatches))
        let shift = maxShift * confidence
        guard shift > 0 else { return base }

        // Affinities we can measure from the snapshot (mean over catches that
        // carry the data). Wind/tide aren't captured yet — omitted here, so they
        // sit at the reference below and keep their base weight.
        var affinity: [ScoreFactor.Kind: Double] = [:]
        if let a = mean(sample.map(pressureAffinity)) { affinity[.pressure] = a }
        if let a = mean(sample.map(moonAffinity)) { affinity[.solunar] = a }
        if let a = mean(sample.map { seasonAffinity($0, species: species) }) { affinity[.season] = a }
        if let a = mean(sample.map(windAffinity)) { affinity[.wind] = a }
        if let a = mean(sample.map(tideAffinity)) { affinity[.tide] = a }

        guard !affinity.isEmpty else { return base }
        let reference = affinity.values.reduce(0, +) / Double(affinity.count)
        guard reference > 0 else { return base }

        func scaled(_ weight: Double, _ kind: ScoreFactor.Kind) -> Double {
            let aff = affinity[kind] ?? reference       // unmeasured → reference → unchanged
            return weight * pow(aff / reference, shift)
        }
        return FactorWeights(
            solunar: scaled(base.solunar, .solunar),
            pressure: scaled(base.pressure, .pressure),
            wind: scaled(base.wind, .wind),
            tide: scaled(base.tide, .tide),
            season: scaled(base.season, .season)
        ).normalized
    }

    // MARK: - Sample selection (per-species, falling back to all catches)

    private static func sample(_ catches: [CatchEntry], species: Species) -> [CatchEntry] {
        guard species != .all else { return catches }
        let forSpecies = catches.filter { $0.species == species }
        return forSpecies.count >= minCatches ? forSpecies : catches
    }

    // MARK: - Per-factor affinity from the catch snapshot (0…1; nil if unknown)

    static func pressureAffinity(_ entry: CatchEntry) -> Double? {
        guard let t = entry.pressureTendency?.lowercased() else { return nil }
        if t.contains("fall") { return 1.0 }
        if t.contains("stead") { return 0.65 }
        if t.contains("ris") { return 0.45 }
        return nil
    }

    static func moonAffinity(_ entry: CatchEntry) -> Double? {
        guard let m = entry.moonPhase?.lowercased() else { return nil }
        if m.contains("full") || m.contains("new") { return 1.0 }
        if m.contains("gibbous") || m.contains("crescent") { return 0.7 }
        if m.contains("quarter") { return 0.5 }
        return nil
    }

    /// Wind favorability, mirroring the scorer's piecewise wind curve. Only set
    /// on catches logged with live weather (older catches have no wind).
    static func windAffinity(_ entry: CatchEntry) -> Double? {
        guard let mph = entry.windMph else { return nil }
        switch mph {
        case ..<2: return 0.55
        case 2..<6: return 0.85
        case 6..<13: return 1.0
        case 13..<19: return 0.65
        case 19..<25: return 0.4
        default: return 0.2
        }
    }

    /// Tide favorability — moving water is prime, slack is poor. Set only on
    /// catches logged at a coastal spot with loaded tide data.
    static func tideAffinity(_ entry: CatchEntry) -> Double? {
        guard let phase = entry.tidePhase?.lowercased() else { return nil }
        if phase.contains("slack") { return 0.4 }
        if phase.contains("rising") || phase.contains("falling") { return 1.0 }
        return nil
    }

    static func seasonAffinity(_ entry: CatchEntry, species: Species) -> Double? {
        let month = Calendar.current.component(.month, from: entry.date)
        let peaks = species.peakMonths
        guard !peaks.isEmpty else { return nil }
        if peaks.contains(month) { return 1.0 }
        let dist = peaks.map { min(abs($0 - month), 12 - abs($0 - month)) }.min() ?? 6
        switch dist {
        case 1: return 0.7
        case 2: return 0.55
        default: return 0.35
        }
    }

    private static func mean(_ values: [Double?]) -> Double? {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        return present.reduce(0, +) / Double(present.count)
    }
}
