import SwiftUI

/// A deterministic, glanceable 0–100 rating of how fishable today is right now,
/// for the active species and conditions. Each factor carries its own weight,
/// raw value, and human-readable reason so we can show a breakdown.
struct FishingScore: Equatable {
    let factors: [ScoreFactor]

    /// Sum of each factor's contribution, clamped to 0–100.
    var overall: Int {
        max(0, min(100, factors.map(\.contribution).reduce(0, +)))
    }

    /// A short label that matches the score band.
    var summary: String {
        switch overall {
        case 85...: "Excellent"
        case 70..<85: "Strong"
        case 50..<70: "Fair"
        case 30..<50: "Tough"
        default: "Poor"
        }
    }

    var tint: Color {
        switch overall {
        case 85...: .green
        case 70..<85: .mint
        case 50..<70: .teal
        case 30..<50: .orange
        default: .red
        }
    }
}

/// The relative weight of each scoring factor. Defaults to the fixed studio
/// weights; the "learns your catches" personalization produces tuned instances
/// (renormalized to sum to 1) from a user's catch history.
struct FactorWeights: Equatable {
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

struct ScoreFactor: Identifiable, Equatable {
    enum Kind: String {
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

    /// Integer points contributed to the overall score.
    var contribution: Int {
        Int((weight * raw * 100).rounded())
    }

    var symbolName: String { kind.symbolName }
}

