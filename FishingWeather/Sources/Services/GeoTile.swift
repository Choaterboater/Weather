import Foundation

enum GeoTile {
    /// Returns a rounded key for (lat, lon) at the given precision in degrees.
    /// Defaults to 0.1° (~11 km), matching previous behavior.
    static func key(lat: Double, lon: Double, precision: Double = 0.1) -> String {
        func round(_ v: Double) -> Double {
            (v / precision).rounded() * precision
        }
        let rlat = round(lat)
        let rlon = round(lon)
        return "\(rlat),\(rlon)"
    }
}
