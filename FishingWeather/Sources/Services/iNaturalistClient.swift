import CoreLocation
import Foundation
import Observation

/// A community-verified species observation pulled from iNaturalist's public
/// API (`api.inaturalist.org`). No auth required for read access. Used to
/// show "recently seen nearby" intel on the Species Guide.
struct SpeciesSighting: Identifiable, Equatable {
    let id: Int           // iNat observation id
    let observedOn: Date
    let latitude: Double
    let longitude: Double
    let placeGuess: String?
    let thumbnailURL: URL?

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

/// Fetches recent research-grade observations of a given species near a
/// location. Results are cached briefly per (species, tile) so flipping
/// between species in the guide is responsive.
@MainActor
@Observable
final class INaturalistClient {
    private(set) var sightings: [Species: [SpeciesSighting]] = [:]
    private(set) var isLoading: Set<Species> = []
    private(set) var lastError: [Species: String] = [:]

    private struct CacheEntry { let timestamp: Date; let sightings: [SpeciesSighting] }
    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 60 * 60 * 6 // 6 h
    private var loadID: [Species: Int] = [:]

    func loadSightings(for species: Species, near location: CLLocation, radiusMiles: Double = 50) async {
        guard let taxonName = species.scientificName else {
            sightings[species] = []
            return
        }
        let key = Self.cacheKey(species: species, location: location)
        // Always bump so an in-flight fetch for another tile can't overwrite us.
        let id = (loadID[species] ?? 0) + 1
        loadID[species] = id

        if let entry = cache[key], -entry.timestamp.timeIntervalSinceNow < cacheTTL {
            sightings[species] = entry.sightings
            lastError[species] = nil
            isLoading.remove(species)
            return
        }

        isLoading.insert(species)
        lastError[species] = nil
        // Clear prior-location results so the UI doesn't label them "nearby".
        sightings[species] = []
        do {
            let fetched = try await fetch(taxonName: taxonName, near: location, radiusMiles: radiusMiles)
            guard loadID[species] == id else { return }
            cache[key] = CacheEntry(timestamp: .now, sightings: fetched)
            sightings[species] = fetched
            isLoading.remove(species)
        } catch {
            guard loadID[species] == id else { return }
            isLoading.remove(species)
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            lastError[species] = error.localizedDescription
            sightings[species] = []
        }
    }

    private func fetch(taxonName: String, near location: CLLocation, radiusMiles: Double) async throws -> [SpeciesSighting] {
        let radiusKm = radiusMiles * 1.609
        var components = URLComponents(string: "https://api.inaturalist.org/v1/observations")!
        let calendar = Calendar.current
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: .now) ?? .now
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]

        components.queryItems = [
            URLQueryItem(name: "taxon_name", value: taxonName),
            // 2 decimals ≈ 1.1 km — plenty for a 50 mi radius, and it keeps
            // precise user coordinates out of a third party's request logs.
            URLQueryItem(name: "lat", value: String(format: "%.2f", location.coordinate.latitude)),
            URLQueryItem(name: "lng", value: String(format: "%.2f", location.coordinate.longitude)),
            URLQueryItem(name: "radius", value: String(radiusKm)),
            URLQueryItem(name: "order_by", value: "observed_on"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "quality_grade", value: "research"),
            URLQueryItem(name: "geo", value: "true"),
            URLQueryItem(name: "per_page", value: "8"),
            URLQueryItem(name: "d1", value: isoFormatter.string(from: oneYearAgo))
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("BiteCast/0.1", forHTTPHeaderField: "User-Agent")
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        // iNat throttles at ~60 req/min; surface a 429 as "busy", not a decode error.
        try HTTPStatusError.validate(urlResponse)
        let response = try JSONDecoder().decode(Response.self, from: data)
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.timeZone = TimeZone(secondsFromGMT: 0)

        return response.results.compactMap { result in
            guard let date = result.observed_on.flatMap(dateFmt.date(from:)),
                  let location = result.location else { return nil }
            let parts = location.split(separator: ",")
            guard parts.count == 2,
                  let lat = Double(parts[0]),
                  let lon = Double(parts[1]) else { return nil }
            let thumb = result.taxon?.default_photo?.square_url.flatMap(URL.init(string:))
            return SpeciesSighting(
                id: result.id,
                observedOn: date,
                latitude: lat,
                longitude: lon,
                placeGuess: result.place_guess,
                thumbnailURL: thumb
            )
        }
    }

    private static func cacheKey(species: Species, location: CLLocation) -> String {
        let lat = (location.coordinate.latitude * 10).rounded() / 10
        let lon = (location.coordinate.longitude * 10).rounded() / 10
        return "\(species.rawValue)-\(lat),\(lon)"
    }

    // MARK: - Decoding

    private struct Response: Decodable {
        let results: [ObservationDTO]
    }

    private struct ObservationDTO: Decodable {
        let id: Int
        let observed_on: String?
        let location: String?            // "lat,lon"
        let place_guess: String?
        let taxon: TaxonDTO?
    }

    private struct TaxonDTO: Decodable {
        let default_photo: PhotoDTO?
    }

    private struct PhotoDTO: Decodable {
        let square_url: String?
    }
}
