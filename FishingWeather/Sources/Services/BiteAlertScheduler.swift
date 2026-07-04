import Foundation

/// Turns a `WeekOutlook` into the set of bite-window notifications to schedule.
/// Pure and deterministic — the delivery layer (UNUserNotificationCenter) reads
/// this list; it holds no scheduling policy of its own.
enum BiteAlertScheduler {
    static func plan(from outlook: WeekOutlook, preferences prefs: AlertPreferences,
                     now: Date = .now) -> [BiteAlert] {
        guard prefs.enabled else { return [] }
        let lead = TimeInterval(prefs.leadMinutes * 60)

        return outlook.windows
            .filter { $0.confidence == .high && $0.score >= prefs.minScore }
            .compactMap { window -> BiteAlert? in
                let fireDate = window.start.addingTimeInterval(-lead)
                // Skip windows too close to fire usefully (or already past).
                guard fireDate > now else { return nil }
                return BiteAlert(
                    id: "bite-\(Int(window.start.timeIntervalSince1970))",
                    fireDate: fireDate,
                    windowStart: window.start,
                    score: window.score,
                    period: window.period,
                    title: "\(window.period.rawValue) bite window",
                    body: body(for: window, at: outlook.locationName)
                )
            }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(prefs.maxAlerts)
            .map { $0 }
    }

    private static func body(for window: ScoredWindow, at location: String) -> String {
        let time = window.start.formatted(date: .omitted, time: .shortened)
        let why = window.factors.prefix(2).joined(separator: ", ")
        let tail = why.isEmpty ? "" : " \(why)."
        return "\(window.species.displayName) · score \(window.score) at \(location), \(time).\(tail)"
    }
}
