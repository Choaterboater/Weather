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

struct ScoreFactor: Identifiable, Equatable {
    enum Kind: String { case solunar, pressure, wind, tide, season }
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

    var symbolName: String {
        switch kind {
        case .solunar: "moon.stars"
        case .pressure: "barometer"
        case .wind: "wind"
        case .tide: "water.waves"
        case .season: "calendar"
        }
    }
}

