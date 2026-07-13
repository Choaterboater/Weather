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
    let creator: String
    let observationURL: URL
    let photo: SpeciesSightingPhoto?

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    var thumbnailURL: URL? { photo?.thumbnailURL }
}

struct SpeciesSightingPhoto: Equatable {
    let thumbnailURL: URL
    let licenseCode: String
    let licenseURL: URL
    let attribution: String
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
        let request = try Self.request(
            taxonName: taxonName,
            near: location,
            radiusMiles: radiusMiles,
            now: .now
        )
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        // iNat throttles at ~60 req/min; surface a 429 as "busy", not a decode error.
        try HTTPStatusError.validate(urlResponse)
        return try Self.sightings(from: data)
    }

    nonisolated static func request(
        taxonName: String,
        near location: CLLocation,
        radiusMiles: Double,
        now: Date
    ) throws -> URLRequest {
        let radiusKm = radiusMiles * 1.609
        var components = URLComponents(string: "https://api.inaturalist.org/v1/observations")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]
        let coordinate = ExternalRequestPrivacy.coordinateComponents(
            location,
            decimalPlaces: 2
        )

        components.queryItems = [
            URLQueryItem(name: "taxon_name", value: taxonName),
            URLQueryItem(name: "lat", value: coordinate.latitude),
            URLQueryItem(name: "lng", value: coordinate.longitude),
            URLQueryItem(
                name: "radius",
                value: String(
                    format: "%.1f",
                    locale: Locale(identifier: "en_US_POSIX"),
                    radiusKm
                )
            ),
            URLQueryItem(name: "order_by", value: "observed_on"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "quality_grade", value: "research"),
            URLQueryItem(name: "geo", value: "true"),
            URLQueryItem(name: "per_page", value: "8"),
            URLQueryItem(name: "photo_license", value: "cc0,cc-by,pd"),
            URLQueryItem(name: "d1", value: isoFormatter.string(from: oneYearAgo))
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(AppIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    nonisolated static func imageRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(AppIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return request
    }

    nonisolated static func sightings(from data: Data) throws -> [SpeciesSighting] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.timeZone = TimeZone(secondsFromGMT: 0)
        dateFmt.locale = Locale(identifier: "en_US_POSIX")

        return response.results.compactMap { result in
            guard let date = result.observed_on.flatMap(dateFmt.date(from:)),
                  let location = result.location,
                  let creator = cleaned(result.user?.name) ?? cleaned(result.user?.login),
                  let observationURL = URL(
                    string: "https://www.inaturalist.org/observations/\(result.id)"
                  )
            else { return nil }
            let parts = location.split(separator: ",")
            guard parts.count == 2,
                  let lat = Double(parts[0]),
                  let lon = Double(parts[1]) else { return nil }
            return SpeciesSighting(
                id: result.id,
                observedOn: date,
                latitude: lat,
                longitude: lon,
                placeGuess: result.place_guess,
                creator: creator,
                observationURL: observationURL,
                photo: result.photos?.lazy.compactMap(safePhoto).first
            )
        }
    }

    private nonisolated static func safePhoto(_ value: PhotoDTO) -> SpeciesSightingPhoto? {
        guard let rawURL = cleaned(value.url ?? value.square_url),
              let thumbnailURL = URL(string: rawURL),
              thumbnailURL.scheme?.lowercased() == "https",
              let rawLicense = cleaned(value.license_code)?.lowercased(),
              let license = allowedLicense(rawLicense),
              let attribution = cleaned(value.attribution)
        else { return nil }

        return SpeciesSightingPhoto(
            thumbnailURL: thumbnailURL,
            licenseCode: license.code,
            licenseURL: license.url,
            attribution: attribution
        )
    }

    private nonisolated static func allowedLicense(
        _ value: String
    ) -> (code: String, url: URL)? {
        switch value {
        case "cc0":
            return (
                "CC0",
                URL(string: "https://creativecommons.org/publicdomain/zero/1.0/")!
            )
        case "pd", "public-domain":
            return (
                "Public Domain",
                URL(string: "https://creativecommons.org/publicdomain/mark/1.0/")!
            )
        case "cc-by":
            return (
                "CC BY",
                URL(string: "https://creativecommons.org/licenses/by/4.0/")!
            )
        default:
            return nil
        }
    }

    private nonisolated static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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
        let user: UserDTO?
        let photos: [PhotoDTO]?
    }

    private struct UserDTO: Decodable {
        let login: String?
        let name: String?
    }

    private struct PhotoDTO: Decodable {
        let url: String?
        let square_url: String?
        let license_code: String?
        let attribution: String?
    }
}
