import Foundation

/// A high or low tide prediction for a specific station and time.
struct TideEvent: Identifiable, Equatable {
    enum Kind: String, Codable {
        case high
        case low

        var label: String {
            switch self {
            case .high: "High"
            case .low: "Low"
            }
        }

        var symbolName: String {
            switch self {
            case .high: "arrow.up.right"
            case .low: "arrow.down.right"
            }
        }
    }

    let id = UUID()
    let time: Date
    let kind: Kind
    let heightFeet: Double?
}

/// One sample on the continuous tide curve, used by the chart.
struct TideSample: Identifiable, Equatable {
    let id = UUID()
    let time: Date
    let heightFeet: Double
}

/// A NOAA tide-prediction station.
struct TideStation: Identifiable, Equatable {
    let id: String        // e.g. "8729840"
    let name: String      // e.g. "Pensacola Bay Entrance"
    let latitude: Double
    let longitude: Double
}
