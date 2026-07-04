import Foundation

enum GeoTile {
    /// Returns a rounded key for (lat, lon) at the given precision in degrees.
    /// Defaults to 0.1° (~11 km). Keys are integer tile indices, not rounded
    /// coordinates: interpolating `(v / p).rounded() * p` can produce float
    /// artifacts like "30.200000000000003" that silently split a tile.
    static func key(lat: Double, lon: Double, precision: Double = 0.1) -> String {
        "\(Int((lat / precision).rounded())),\(Int((lon / precision).rounded()))"
    }
}
