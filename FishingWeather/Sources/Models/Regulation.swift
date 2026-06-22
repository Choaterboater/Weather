import Foundation

/// A single state's harvest regulation for one species. Hand-curated from the
/// state agency's published rules. Always show `sourceURL` + `lastVerifiedDate`
/// to the user — regulations change and we don't want to be the authoritative source.
struct Regulation: Codable, Equatable, Identifiable {
    let speciesId: String       // matches Species.rawValue
    let waterType: WaterType
    let minSizeInches: Double?  // minimum keepable length, if any
    let maxSizeInches: Double?  // maximum keepable length (top of a slot)
    let slotDescription: String?
    let dailyBagLimit: Int?     // nil means no published bag limit
    let seasonClosures: [SeasonClosure]
    let notes: String?

    var id: String { "\(speciesId)" }

    /// True if `date` falls inside any closed season window (year-agnostic).
    func isClosed(on date: Date, calendar: Calendar = .current) -> Bool {
        seasonClosures.contains { $0.contains(date, calendar: calendar) }
    }
}

/// A single date-range closure within a year. `startMonthDay` / `endMonthDay`
/// are MM-DD strings so they apply every year without manual rollover.
struct SeasonClosure: Codable, Equatable {
    let start: String   // "MM-DD"
    let end: String     // "MM-DD"
    let label: String

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let startDate = Self.date(from: start, year: calendar.component(.year, from: date), calendar: calendar),
              let endDate = Self.date(from: end, year: calendar.component(.year, from: date), calendar: calendar) else {
            return false
        }
        if startDate <= endDate {
            return date >= startDate && date <= endDate
        } else {
            // Closure wraps the new year (e.g. Dec 15 – Jan 5).
            return date >= startDate || date <= endDate
        }
    }

    private static func date(from monthDay: String, year: Int, calendar: Calendar) -> Date? {
        let parts = monthDay.split(separator: "-")
        guard parts.count == 2,
              let month = Int(parts[0]),
              let day = Int(parts[1]) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }
}

/// One state's full ruleset — what RegulationStore loads from each bundled JSON.
struct StateRegulations: Codable {
    let stateCode: String
    let stateName: String
    let sourceURL: URL
    let lastVerifiedDate: String   // ISO yyyy-MM-dd
    let regulations: [Regulation]
}
