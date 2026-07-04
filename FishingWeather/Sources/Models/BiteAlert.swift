import Foundation

/// A single scheduled bite-window notification, derived from the week outlook.
struct BiteAlert: Identifiable, Equatable {
    /// Stable per window (its start time) so re-planning replaces rather than
    /// duplicates a pending notification.
    let id: String
    let fireDate: Date
    let windowStart: Date
    let score: Int
    let period: BitePeriod
    let title: String
    let body: String
}

/// User controls for smart bite alerts. Defaults are conservative: opt-in, only
/// strong windows, a useful head start, and a small daily/weekly cap.
struct AlertPreferences: Equatable, Codable {
    var enabled: Bool = false
    /// Only windows scoring at least this alert.
    var minScore: Int = 70
    /// How long before the window starts to notify.
    var leadMinutes: Int = 45
    /// Ceiling on how many notifications are scheduled at once.
    var maxAlerts: Int = 5

    static let `default` = AlertPreferences()
}
