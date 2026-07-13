import Foundation

/// One scored solunar window in the week outlook — a specific fishing window on
/// a specific day, with its 0–100 score and the confidence in that score.
struct ScoredWindow: Identifiable {
    enum Confidence { case high, low }

    let id = UUID()
    let date: Date          // start of the window's day, for grouping
    let start: Date
    let end: Date
    let score: Int          // 0–100
    let confidence: Confidence
    let period: BitePeriod  // .major / .minor — the solunar window this is
    let factors: [String]   // top reasons, most influential first
    let species: Species
}

/// The ranked outlook for the coming week: the best fishing windows for the
/// active location and species, sorted best-first.
struct WeekOutlook {
    let locationName: String
    let generatedAt: Date
    let windows: [ScoredWindow]

    var isEmpty: Bool { windows.isEmpty }
}

/// Provider-neutral inputs for one forecast day.
struct DayForecastInput {
    let date: Date          // start of day
    let moonrise: Date?
    let moonset: Date?
    let moonPhase: LunarPhase
    let dailyWindMph: Double?
}
