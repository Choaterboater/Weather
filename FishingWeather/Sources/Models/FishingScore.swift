import SwiftUI

/// The single 0–100 bite-score vocabulary used by every score surface.
/// Keep threshold decisions here so cards, charts, planners, and forecast
/// details cannot drift into contradictory labels or colors.
enum BiteScoreBand: String, CaseIterable, Identifiable, Sendable {
    case excellent
    case strong
    case fair
    case tough
    case poor

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var rangeLabel: String {
        switch self {
        case .excellent: "85–100"
        case .strong: "70–84"
        case .fair: "50–69"
        case .tough: "30–49"
        case .poor: "0–29"
        }
    }

    static func band(for score: Int) -> BiteScoreBand? {
        guard (0...100).contains(score) else { return nil }
        return switch score {
        case 85...: .excellent
        case 70..<85: .strong
        case 50..<70: .fair
        case 30..<50: .tough
        default: .poor
        }
    }
}

/// A deterministic, glanceable 0–100 rating of how fishable today is right now,
/// for the active species and conditions. Each factor carries its own weight,
/// raw value, and human-readable reason so we can show a breakdown.
struct FishingScore: Equatable, Sendable {
    let factors: [ScoreFactor]

    /// Rounded weighted sum, clamped to 0–100.
    ///
    /// Deliberately computed from the unrounded factor values rather than by
    /// summing `ScoreFactor.contribution`: rounding each factor first can drift
    /// the total by a couple of points, which is enough to cross a
    /// `BiteScoreBand` boundary and contradict the breakdown shown beneath it.
    var overall: Int {
        let total = factors
            .map(\.weightedValue)
            .filter(\.isFinite)
            .reduce(0, +)
        guard total.isFinite else { return 0 }
        return max(0, min(100, Int((total * 100).rounded())))
    }

    var band: BiteScoreBand {
        BiteScoreBand.band(for: overall) ?? .poor
    }

    /// A short label that matches the score band.
    var summary: String {
        band.title
    }

    var tint: Color {
        band.color
    }
}

/// The relative weight of each scoring factor. Defaults to the fixed studio
/// weights; the "learns your catches" personalization produces tuned instances
/// (renormalized to sum to 1) from a user's catch history.
struct FactorWeights: Equatable, Sendable {
    var solunar: Double
    var pressure: Double
    var wind: Double
    var tide: Double
    var season: Double

    static let standard = FactorWeights(
        solunar: 0.25, pressure: 0.20, wind: 0.15, tide: 0.25, season: 0.15
    )

    /// Renormalized so the five weights sum to 1 (a no-op when they already do).
    var normalized: FactorWeights {
        let total = solunar + pressure + wind + tide + season
        guard total > 0 else { return .standard }
        return FactorWeights(
            solunar: solunar / total, pressure: pressure / total, wind: wind / total,
            tide: tide / total, season: season / total
        )
    }
}

struct ScoreFactor: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case solunar, pressure, wind, tide, season

        var symbolName: String {
            switch self {
            case .solunar: "moon.stars"
            case .pressure: "barometer"
            case .wind: "wind"
            case .tide: "water.waves"
            case .season: "calendar"
            }
        }
    }
    /// Stable across recomputes so charts/ForEach don't thrash every frame.
    var id: String { kind.rawValue }
    let kind: Kind
    let label: String
    /// 0–1 — share of the total score this factor can claim.
    let weight: Double
    /// 0–1 — how favorable this factor is right now.
    let raw: Double
    /// Plain-language reason: what we observed and why it pulled the score up or down.
    let detail: String

    /// Unrounded 0–1 share this factor contributes. The basis for `overall`.
    var weightedValue: Double {
        weight * raw
    }

    /// Integer points contributed, for display only. `FishingScore.overall`
    /// intentionally does not sum these — see its documentation.
    var contribution: Int {
        let value = weightedValue * 100
        guard value.isFinite else { return 0 }
        return Int(value.rounded())
    }

    var symbolName: String { kind.symbolName }
}
