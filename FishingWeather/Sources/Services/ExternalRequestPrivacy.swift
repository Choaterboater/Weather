import CoreLocation
import Foundation

enum ExternalRequestPrivacy {
    static func coordinateString(
        _ location: CLLocation,
        decimalPlaces: Int
    ) -> String {
        precondition((0...6).contains(decimalPlaces))
        return String(
            format: "%.*f,%.*f",
            locale: Locale(identifier: "en_US_POSIX"),
            decimalPlaces,
            normalizedZero(location.coordinate.latitude, decimalPlaces: decimalPlaces),
            decimalPlaces,
            normalizedZero(location.coordinate.longitude, decimalPlaces: decimalPlaces)
        )
    }

    static func coordinateComponents(
        _ location: CLLocation,
        decimalPlaces: Int
    ) -> (latitude: String, longitude: String) {
        let components = coordinateString(location, decimalPlaces: decimalPlaces)
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        return (String(components[0]), String(components[1]))
    }

    private static func normalizedZero(_ value: Double, decimalPlaces: Int) -> Double {
        let scale = pow(10.0, Double(decimalPlaces))
        let rounded = (value * scale).rounded() / scale
        return rounded == 0 ? 0 : rounded
    }
}

enum ExternalServiceAttribution {
    static let openStreetMapURL = URL(
        string: "https://www.openstreetmap.org/copyright"
    )!
    static let openStreetMapLabel = "© OpenStreetMap contributors"

    static let iNaturalistURL = URL(string: "https://www.inaturalist.org")!
}
