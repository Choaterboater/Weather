import CoreLocation

/// What kind of water/structure a fishing spot is. Drives iconography and copy.
enum SpotKind: String, CaseIterable, Codable, Identifiable {
    case lake
    case pond
    case creek
    case river
    case bay
    case surf
    case pier
    case jetty
    case reef
    case flat
    case ramp
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lake: "Lake"
        case .pond: "Pond"
        case .creek: "Creek"
        case .river: "River"
        case .bay: "Bay"
        case .surf: "Surf"
        case .pier: "Pier"
        case .jetty: "Jetty"
        case .reef: "Reef"
        case .flat: "Flat"
        case .ramp: "Boat Ramp"
        case .other: "Spot"
        }
    }

    var symbolName: String {
        switch self {
        case .lake, .pond: "drop.fill"
        case .creek, .river: "water.waves"
        case .bay: "water.waves.and.arrow.trianglehead.up"
        case .surf: "water.waves"
        case .pier, .jetty: "figure.fishing"
        case .reef: "fish"
        case .flat: "circle.dotted"
        case .ramp: "car.fill"
        case .other: "mappin"
        }
    }
}

/// A saved location the angler can switch to instead of their current GPS spot.
///
/// All metadata beyond `name` and coordinates is optional so legacy persisted
/// spots (before the metadata expansion) still decode cleanly.
struct FishingSpot: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var waterType: WaterType?
    var kind: SpotKind?
    var stateCode: String?
    var targetSpecies: [Species]?
    var notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        waterType: WaterType? = nil,
        kind: SpotKind? = nil,
        stateCode: String? = nil,
        targetSpecies: [Species]? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.waterType = waterType
        self.kind = kind
        self.stateCode = stateCode
        self.targetSpecies = targetSpecies
        self.notes = notes
    }

    init(
        id: UUID = UUID(),
        name: String,
        location: CLLocation,
        waterType: WaterType? = nil,
        kind: SpotKind? = nil,
        stateCode: String? = nil,
        targetSpecies: [Species]? = nil,
        notes: String? = nil
    ) {
        self.init(
            id: id,
            name: name,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            waterType: waterType,
            kind: kind,
            stateCode: stateCode,
            targetSpecies: targetSpecies,
            notes: notes
        )
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// Same place even when UUIDs differ (legacy curated saves used random IDs).
    func isSamePlace(as other: FishingSpot) -> Bool {
        name == other.name
            && abs(latitude - other.latitude) < 0.0001
            && abs(longitude - other.longitude) < 0.0001
    }
}
