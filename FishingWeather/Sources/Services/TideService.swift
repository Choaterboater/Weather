import CoreLocation
import Foundation
import Observation

/// Fetches NOAA CO-OPS tide predictions for the user's current location or
/// selected spot. Free public API — no auth required.
///
/// Behavior:
/// * Stations metadata (~3,000 entries) is fetched once and cached on disk; nearest
///   station is computed locally.
/// * If the nearest station is farther than `maxStationDistanceMiles` we treat the
///   spot as effectively inland and surface no tide data.
/// * Predictions are fetched in two passes: `hilo` for the labeled high/low events,
///   plus hourly samples for a smooth curve.
@MainActor
@Observable
final class TideService {
    private(set) var events: [TideEvent] = []
    private(set) var samples: [TideSample] = []
    private(set) var station: TideStation?
    private(set) var distanceMiles: Double?
    private(set) var isLoading = false
    private(set) var lastError: String?

    /// Spots farther than this from any tide station get no tide data.
    let maxStationDistanceMiles: Double = 50

    private var stations: [TideStation] = []
    private var lastKey: String?

    func load(near location: CLLocation, on date: Date = .now) async {
        let key = Self.locationKey(location, date: date)
        if key == lastKey { return }
        lastKey = key

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            if stations.isEmpty {
                stations = try await fetchStations()
            }
            guard let nearest = nearestStation(to: location) else {
                clear()
                return
            }
            let miles = location.distance(from: CLLocation(
                latitude: nearest.latitude, longitude: nearest.longitude
            )) / 1609.34
            guard miles <= maxStationDistanceMiles else {
                clear()
                return
            }
            self.station = nearest
            self.distanceMiles = miles
            async let hilo = fetchPredictions(stationId: nearest.id, date: date, interval: "hilo")
            async let hourly = fetchPredictions(stationId: nearest.id, date: date, interval: "h")
            let hiloResults = try await hilo
            let hourlyResults = try await hourly
            self.events = hiloResults.compactMap(\.event)
            self.samples = hourlyResults.map { TideSample(time: $0.time, heightFeet: $0.value) }
        } catch {
            lastError = error.localizedDescription
            clear()
        }
    }

    private func clear() {
        events = []
        samples = []
        station = nil
        distanceMiles = nil
    }

    private func nearestStation(to location: CLLocation) -> TideStation? {
        stations.min { a, b in
            let da = location.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude))
            let db = location.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            return da < db
        }
    }

    // MARK: - Networking

    private struct StationListResponse: Decodable {
        let stations: [StationDTO]
    }
    private struct StationDTO: Decodable {
        let id: String
        let name: String
        let lat: Double
        let lng: Double
    }

    private func fetchStations() async throws -> [TideStation] {
        let url = URL(string: "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(StationListResponse.self, from: data)
        return decoded.stations.map {
            TideStation(id: $0.id, name: $0.name, latitude: $0.lat, longitude: $0.lng)
        }
    }

    private struct PredictionsResponse: Decodable {
        let predictions: [PredictionDTO]?
    }
    private struct PredictionDTO: Decodable {
        let t: String   // "yyyy-MM-dd HH:mm"
        let v: String   // height in feet
        let type: String? // "H" or "L" when interval=hilo
    }

    private struct PredictionPoint {
        let time: Date
        let value: Double
        let kind: TideEvent.Kind?
        var event: TideEvent? {
            guard let kind else { return nil }
            return TideEvent(time: time, kind: kind, heightFeet: value)
        }
    }

    private func fetchPredictions(stationId: String, date: Date, interval: String) async throws -> [PredictionPoint] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone.current
        let day = formatter.string(from: date)

        var components = URLComponents(string: "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter")!
        components.queryItems = [
            URLQueryItem(name: "product", value: "predictions"),
            URLQueryItem(name: "application", value: "BiteCast"),
            URLQueryItem(name: "station", value: stationId),
            URLQueryItem(name: "begin_date", value: day),
            URLQueryItem(name: "end_date", value: day),
            URLQueryItem(name: "datum", value: "MLLW"),
            URLQueryItem(name: "units", value: "english"),
            URLQueryItem(name: "time_zone", value: "lst_ldt"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "interval", value: interval)
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let decoded = try JSONDecoder().decode(PredictionsResponse.self, from: data)
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "yyyy-MM-dd HH:mm"
        timeFmt.timeZone = TimeZone.current
        return (decoded.predictions ?? []).compactMap { dto in
            guard let t = timeFmt.date(from: dto.t),
                  let v = Double(dto.v) else { return nil }
            let kind: TideEvent.Kind?
            switch dto.type {
            case "H": kind = .high
            case "L": kind = .low
            default: kind = nil
            }
            return PredictionPoint(time: t, value: v, kind: kind)
        }
    }

    private static func locationKey(_ location: CLLocation, date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        return "\(lat),\(lon)-\(fmt.string(from: date))"
    }
}
