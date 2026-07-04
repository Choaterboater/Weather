import Foundation

/// A solunar feeding period. Major periods are stronger and longer than minor ones.
enum BitePeriod: String {
    case major = "Major"
    case minor = "Minor"

    /// Typical length of the feeding window centered on its peak.
    var duration: TimeInterval {
        switch self {
        case .major: 2 * 3600
        case .minor: 1 * 3600
        }
    }
}

/// A single bite window with a peak time and a span around it.
struct BiteWindow: Identifiable {
    /// Stable across `FishingConditions` recomputes (conditions is derived state).
    var id: String { "\(period.rawValue)|\(peak.timeIntervalSince1970)|\(cause)" }
    let period: BitePeriod
    let peak: Date
    let start: Date
    let end: Date
    /// What drives this window, e.g. "Moon overhead" or "Moonrise".
    let cause: String

    init(period: BitePeriod, peak: Date, cause: String) {
        self.period = period
        self.peak = peak
        self.cause = cause
        self.start = peak.addingTimeInterval(-period.duration / 2)
        self.end = peak.addingTimeInterval(period.duration / 2)
    }

    func isActive(at date: Date) -> Bool {
        (start...end).contains(date)
    }
}
