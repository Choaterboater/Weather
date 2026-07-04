import CoreLocation
import Foundation
import Observation

/// A community-tagged fishing access point pulled from OpenStreetMap via the
/// Overpass API. Variable quality — surfaced as a discrete list separate from
/// our curated spots so users can tell the two apart.
struct RampPin: Identifiable, Equatable {
    enum Kind: String {
        case boatRamp
        case fishingSite
        case pier

        var displayName: String {
            switch self {
            case .boatRamp: "Boat Ramp"
            case .fishingSite: "Fishing Spot"
            case .pier: "Pier"
            }
        }

        var symbolName: String {
            switch self {
            case .boatRamp: "car.fill"
            case .fishingSite: "figure.fishing"
            case .pier: "figure.fishing"
            }
        }
    }

    let id: Int          // OSM node/way id
    let name: String?
    let kind: Kind
    let latitude: Double
    let longitude: Double

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

/// Queries the OpenStreetMap Overpass API for nearby boat ramps, public piers,
/// and tagged fishing sites. Cached briefly per coarsened lat/lon tile to be
/// nice to the public endpoint.
@MainActor
@Observable
final class OpenStreetMapClient {
    private(set) var ramps: [RampPin] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    private struct CacheEntry { let timestamp: Date; let pins: [RampPin] }
    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 60 * 60 * 12 // 12h
    private var loadID = 0

    func loadRamps(near location: CLLocation, radiusMiles: Double = 25) async {
        let key = Self.tileKey(location)
        // Always bump so an in-flight fetch for another tile can't overwrite us,
        // including when we serve a cache hit.
        loadID += 1
        let id = loadID

        if let entry = cache[key], -entry.timestamp.timeIntervalSinceNow < cacheTTL {
            ramps = entry.pins
            lastError = nil
            isLoading = false
            return
        }

        isLoading = true
        lastError = nil
        do {
            let pins = try await fetch(near: location, radiusMiles: radiusMiles)
            guard id == loadID else { return }
            cache[key] = CacheEntry(timestamp: .now, pins: pins)
            ramps = pins
            isLoading = false
        } catch {
            guard id == loadID else { return }
            isLoading = false
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            lastError = error.localizedDescription
            // Keep the previous list when a refresh fails.
        }
    }

    private func fetch(near location: CLLocation, radiusMiles: Double) async throws -> [RampPin] {
        let meters = Int(radiusMiles * 1609.34)
        // ~1.1 km granularity — matches the cache tile and keeps precise user
        // coordinates out of a third party's request logs.
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        let query = """
        [out:json][timeout:12];
        (
          node["amenity"="boat_ramp"](around:\(meters),\(lat),\(lon));
          way["amenity"="boat_ramp"](around:\(meters),\(lat),\(lon));
          node["leisure"="fishing"](around:\(meters),\(lat),\(lon));
          node["man_made"="pier"]["fishing"="yes"](around:\(meters),\(lat),\(lon));
        );
        out center 80;
        """
        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        request.httpMethod = "POST"
        request.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")".data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("BiteCast/0.1 (https://github.com/secure-ssid)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        // The public Overpass instance routinely answers 429/504 with an HTML
        // body; decode that and the user sees a cryptic "wrong format" error.
        try HTTPStatusError.validate(response)
        let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
        return decoded.elements.compactMap(\.pin)
    }

    private static func tileKey(_ location: CLLocation) -> String {
        let lat = (location.coordinate.latitude * 10).rounded() / 10
        let lon = (location.coordinate.longitude * 10).rounded() / 10
        return "\(lat),\(lon)"
    }

    // MARK: - Decoding

    private struct OverpassResponse: Decodable {
        let elements: [Element]
    }

    private struct Element: Decodable {
        let id: Int
        let type: String
        let lat: Double?
        let lon: Double?
        let center: Center?
        let tags: [String: String]?

        struct Center: Decodable { let lat: Double; let lon: Double }

        var pin: RampPin? {
            let coord: (Double, Double)?
            if let lat, let lon {
                coord = (lat, lon)
            } else if let center {
                coord = (center.lat, center.lon)
            } else {
                coord = nil
            }
            guard let coord else { return nil }
            let tags = tags ?? [:]
            let kind: RampPin.Kind
            if tags["amenity"] == "boat_ramp" {
                kind = .boatRamp
            } else if tags["man_made"] == "pier" {
                kind = .pier
            } else {
                kind = .fishingSite
            }
            return RampPin(id: id, name: tags["name"], kind: kind, latitude: coord.0, longitude: coord.1)
        }
    }
}
