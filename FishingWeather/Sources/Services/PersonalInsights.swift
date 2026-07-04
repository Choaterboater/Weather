import Foundation

/// A plain-language summary of what the catch log taught the Fishing Score, for
/// the "Your Patterns" view. Pure analysis: it reads the tuned weights back out
/// to explain which factors moved, and tallies the catch snapshot for the
/// conditions and baits that produced fish.
struct PersonalInsights {
    let species: Species
    let catchCount: Int
    let factorChanges: [FactorChange]
    let topBaits: [BaitCount]
    let conditions: [ConditionStat]

    /// How a factor's weight moved relative to the standard score.
    struct FactorChange: Identifiable {
        var id: String { kind.rawValue }
        let kind: ScoreFactor.Kind
        let label: String
        let direction: Direction
        enum Direction { case up, down, steady }
    }

    struct BaitCount: Identifiable {
        var id: String { bait.lowercased() }
        let bait: String
        let count: Int
    }

    struct ConditionStat: Identifiable {
        var id: String { label }
        let icon: String
        let label: String
        let detail: String
    }
}

enum PersonalInsightsBuilder {
    static func build(from catches: [CatchEntry], species: Species) -> PersonalInsights? {
        let sample = PersonalScoreModel.informingSample(catches, species: species)
        guard !sample.isEmpty else { return nil }

        let weights = PersonalScoreModel.weights(from: catches, species: species)
        let base = FactorWeights.standard
        let factorChanges: [PersonalInsights.FactorChange] = [
            (ScoreFactor.Kind.solunar, "Solunar", weights.solunar, base.solunar),
            (.pressure, "Pressure", weights.pressure, base.pressure),
            (.wind, "Wind", weights.wind, base.wind),
            (.tide, "Tide", weights.tide, base.tide),
            (.season, "Season", weights.season, base.season),
        ].map { kind, label, personal, standard in
            PersonalInsights.FactorChange(kind: kind, label: label,
                                          direction: direction(personal, standard))
        }

        return PersonalInsights(
            species: species,
            catchCount: sample.count,
            factorChanges: factorChanges,
            topBaits: topBaits(in: sample),
            conditions: conditions(in: sample)
        )
    }

    private static func direction(_ personal: Double, _ standard: Double) -> PersonalInsights.FactorChange.Direction {
        if personal > standard * 1.04 { return .up }
        if personal < standard * 0.96 { return .down }
        return .steady
    }

    private static func topBaits(in sample: [CatchEntry]) -> [PersonalInsights.BaitCount] {
        var tally: [String: (display: String, count: Int)] = [:]
        for entry in sample {
            let bait = entry.bait.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bait.isEmpty else { continue }
            tally[bait.lowercased(), default: (bait, 0)].count += 1
        }
        return tally.values
            .sorted { $0.count > $1.count }
            .prefix(3)
            .map { PersonalInsights.BaitCount(bait: $0.display, count: $0.count) }
    }

    private static func conditions(in sample: [CatchEntry]) -> [PersonalInsights.ConditionStat] {
        var stats: [PersonalInsights.ConditionStat] = []
        let total = sample.count

        if let (label, n) = topCount(sample.compactMap(\.pressureTendency)) {
            stats.append(.init(icon: "barometer", label: "\(label) pressure",
                               detail: "\(n) of \(total) catches"))
        }
        if let (label, n) = topCount(sample.compactMap(\.tidePhase)) {
            stats.append(.init(icon: "water.waves", label: "\(label) tide",
                               detail: "\(n) of \(total) catches"))
        }
        if let (label, n) = topCount(sample.map { timeOfDay(for: $0.date) }) {
            stats.append(.init(icon: "clock", label: label, detail: "\(n) of \(total) catches"))
        }
        if let (label, n) = topCount(sample.compactMap(\.moonPhase)) {
            stats.append(.init(icon: "moon.stars", label: label, detail: "\(n) of \(total) catches"))
        }
        return stats
    }

    private static func timeOfDay(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<8: "Dawn"
        case 8..<11: "Morning"
        case 11..<15: "Midday"
        case 15..<19: "Afternoon"
        case 19..<22: "Evening"
        default: "Night"
        }
    }

    /// The most common value and its count, or nil for an empty list.
    private static func topCount(_ items: [String]) -> (String, Int)? {
        guard !items.isEmpty else { return nil }
        let counts = Dictionary(grouping: items, by: { $0 }).mapValues(\.count)
        guard let best = counts.max(by: { $0.value < $1.value }) else { return nil }
        return (best.key, best.value)
    }
}
