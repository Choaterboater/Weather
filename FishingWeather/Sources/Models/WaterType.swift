import Foundation

/// Whether a fishing spot, species, or rule applies to fresh, salt, or brackish water.
/// Used to filter species pickers and to decide which conditions (e.g. tides) are
/// surfaced for a given spot.
enum WaterType: String, CaseIterable, Codable, Identifiable {
    case freshwater
    case saltwater
    case brackish

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .freshwater: "Freshwater"
        case .saltwater: "Saltwater"
        case .brackish: "Brackish"
        }
    }

    var symbolName: String {
        switch self {
        case .freshwater: "drop.fill"
        case .saltwater: "water.waves"
        case .brackish: "drop.halffull"
        }
    }
}
