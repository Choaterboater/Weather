import Foundation

/// Derives the day's solunar bite windows from moonrise/moonset.
///
/// Solunar theory: fish feed most around the moon's transits (overhead and
/// underfoot → major periods) and around moonrise/moonset (minor periods).
/// WeatherKit gives us rise/set directly; the transits are approximated from
/// the rise/set midpoint, which is accurate enough for planning a trip.
enum SolunarCalculator {
    /// Half a lunar day (~24h50m) — the spacing between successive moon transits.
    private static let halfLunarDay: TimeInterval = 12 * 3600 + 25 * 60

    static func windows(moonrise: Date?, moonset: Date?, on day: Date) -> [BiteWindow] {
        var windows: [BiteWindow] = []

        if let moonrise {
            windows.append(BiteWindow(period: .minor, peak: moonrise, cause: "Moonrise"))
        }
        if let moonset {
            windows.append(BiteWindow(period: .minor, peak: moonset, cause: "Moonset"))
        }

        if let overhead = upperTransit(moonrise: moonrise, moonset: moonset) {
            windows.append(BiteWindow(period: .major, peak: overhead, cause: "Moon overhead"))

            // The opposing (underfoot) transit is ~12h25m away. Prefer the one
            // that falls on the same calendar day; omit it when neither does
            // (overhead near noon can push both off "today").
            let earlier = overhead.addingTimeInterval(-halfLunarDay)
            let later = overhead.addingTimeInterval(halfLunarDay)
            let calendar = Calendar.current
            if calendar.isDate(earlier, inSameDayAs: day) {
                windows.append(BiteWindow(period: .major, peak: earlier, cause: "Moon underfoot"))
            } else if calendar.isDate(later, inSameDayAs: day) {
                windows.append(BiteWindow(period: .major, peak: later, cause: "Moon underfoot"))
            }
        }

        return windows.sorted { $0.peak < $1.peak }
    }

    /// Time the moon is highest (overhead). When only one of rise/set is known,
    /// estimate from a quarter lunar day offset.
    private static func upperTransit(moonrise: Date?, moonset: Date?) -> Date? {
        switch (moonrise, moonset) {
        case let (rise?, set?):
            // If set precedes rise on the clock, that set belongs to the next
            // up-period; estimate overhead from rise alone rather than overshoot.
            guard set > rise else {
                return rise.addingTimeInterval(halfLunarDay / 2)
            }
            return rise.addingTimeInterval(set.timeIntervalSince(rise) / 2)
        case let (rise?, nil):
            return rise.addingTimeInterval(halfLunarDay / 2)
        case let (nil, set?):
            return set.addingTimeInterval(-halfLunarDay / 2)
        default:
            return nil
        }
    }
}
