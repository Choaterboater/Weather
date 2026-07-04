import Foundation

/// The compact bite reading the app shares with its Home/Lock Screen widget.
/// Written to the shared App Group container whenever the app scores conditions;
/// the widget's timeline provider reads the latest one back. Plain, Codable, and
/// free of WeatherKit types so both targets can hold it.
struct WidgetSnapshot: Codable, Equatable {
    var score: Int
    var summary: String          // "Strong", "Fair", …
    var locationName: String
    var speciesName: String
    var nextWindowLabel: String? // e.g. "Major window 6:10 AM"
    var updatedAt: Date

    /// Shown before the app has ever computed a score.
    static let placeholder = WidgetSnapshot(
        score: 72, summary: "Strong", locationName: "Your spot",
        speciesName: "All species", nextWindowLabel: "Major window 6:10 AM",
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}
