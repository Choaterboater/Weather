import CoreLocation

/// A saved location the angler can switch to instead of their current GPS spot.
struct FishingSpot: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    init(id: UUID = UUID(), name: String, location: CLLocation) {
        self.init(
            id: id,
            name: name,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
