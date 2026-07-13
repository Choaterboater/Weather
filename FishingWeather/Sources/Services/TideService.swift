import CoreLocation
import Foundation
import Observation

/// One parsed NOAA prediction point. `kind` is set for labeled high/low events
/// (`interval=hilo`) and nil for hourly curve samples.
struct TidePoint: Equatable, Sendable {
    let time: Date
    let heightFeet: Double
    let kind: TideEvent.Kind?

    var event: TideEvent? {
        guard let kind else { return nil }
        return TideEvent(time: time, kind: kind, heightFeet: heightFeet)
    }
}

/// NOAA CO-OPS returns HTTP 200 with an error envelope instead of a status code.
struct NOAADataError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Inclusive GMT calendar days sent to NOAA for one forecast-local display day.
struct TideRequestDateRange: Equatable, Sendable {
    let beginDate: String
    let endDate: String
    let coverage: Range<Date>
}

/// Fetches NOAA CO-OPS tide predictions for the user's current location or
/// selected spot. Free public API — no auth required.
///
/// Behavior:
/// * Stations metadata (~3,000 entries) is fetched once and cached on disk; nearest
///   station is computed locally.
/// * If the nearest station is farther than `maxStationDistanceMiles` we treat the
///   spot as effectively inland and surface no tide data.
/// * Predictions are fetched in two passes: `hilo` for the labeled high/low events,
///   plus hourly samples for a smooth curve. All timestamps are requested and
///   parsed in GMT so a saved spot renders correctly from any device timezone.
/// * The prediction window spans the forecast-local yesterday–tomorrow range so
///   scoring near midnight still knows about the next event. `events`/`samples`
///   are compatibility slices for the display day; `allEvents`/`allSamples`
///   retain the full response for later day selections and scoring.
@MainActor
@Observable
final class TideService {
    /// The selected day's labeled high/low events, for display compatibility.
    private(set) var events: [TideEvent] = []
    /// The full fetched event window, for scoring and later day selections.
    private(set) var allEvents: [TideEvent] = []
    /// The selected day's hourly curve, for display compatibility.
    private(set) var samples: [TideSample] = []
    /// The full fetched hourly curve, for later day selections.
    private(set) var allSamples: [TideSample] = []
    private(set) var station: TideStation?
    private(set) var distanceMiles: Double?
    private(set) var isLoading = false
    private(set) var lastError: String?

    /// Spots farther than this from any tide station get no tide data.
    let maxStationDistanceMiles: Double = 50

    private var stations: [TideStation] = []
    private var lastKey: String?
    private var loadedLocationKey: String?
    private var loadedCoverage: Range<Date>?
    private var loadID = 0

    func load(
        near location: CLLocation,
        on date: Date = .now,
        calendar: Calendar = .current,
        force: Bool = false
    ) async {
        let key = Self.dataKey(location, date: date, calendar: calendar)
        let locationKey = Self.locationKey(location)
        loadID += 1
        let id = loadID

        if !force, key == lastKey {
            isLoading = false
            return
        }

        // NOAA returns a forecast-local yesterday–tomorrow window. Re-slice an
        // already retained response when the user moves to another covered day.
        if !force,
           loadedLocationKey == locationKey,
           station != nil,
           loadedCoverage.map({
               Self.coversFullDay($0, containing: date, calendar: calendar)
           }) == true,
           Self.hasPredictions(
               events: allEvents,
               samples: allSamples,
               on: date,
               calendar: calendar
           ) {
            events = Self.events(in: allEvents, on: date, calendar: calendar)
            samples = Self.samples(in: allSamples, on: date, calendar: calendar)
            lastKey = key
            isLoading = false
            lastError = nil
            return
        }

        // Drop prior-location tides so the card can't show another station's curve.
        if lastKey != key {
            clear()
            lastKey = nil
        }
        isLoading = true
        lastError = nil

        do {
            if stations.isEmpty {
                let fetched = try await Self.loadStations()
                guard id == loadID else { return }
                stations = fetched
            }
            guard let nearest = nearestStation(to: location) else {
                finishInland(key: key)
                return
            }
            let miles = location.distance(from: CLLocation(
                latitude: nearest.latitude, longitude: nearest.longitude
            )) / 1609.34
            guard miles <= maxStationDistanceMiles else {
                finishInland(key: key)
                return
            }
            let requestRange = Self.requestDateRange(
                containing: date,
                calendar: calendar
            )
            async let hilo = Self.fetchPredictions(
                stationId: nearest.id,
                requestRange: requestRange,
                interval: "hilo"
            )
            async let hourly = Self.fetchPredictions(
                stationId: nearest.id,
                requestRange: requestRange,
                interval: "h"
            )
            let (hiloResults, hourlyResults) = try await (hilo, hourly)
            guard id == loadID else { return }

            station = nearest
            distanceMiles = miles
            allEvents = hiloResults.compactMap(\.event)
            allSamples = hourlyResults.map {
                TideSample(time: $0.time, heightFeet: $0.heightFeet)
            }
            events = Self.events(in: allEvents, on: date, calendar: calendar)
            samples = Self.samples(in: allSamples, on: date, calendar: calendar)
            // Only a successful load suppresses a reload; failures must retry
            // the next time the tab appears.
            lastKey = key
            loadedLocationKey = locationKey
            loadedCoverage = requestRange.coverage
            isLoading = false
        } catch {
            guard id == loadID else { return }
            isLoading = false
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            lastError = error.localizedDescription
            clear()
        }
    }

    /// High/low tide events for the coming `days`, grouped by local day — for
    /// the Weekly Trip Planner's tide factor. Independent of the display load;
    /// returns empty (the planner then scores without tides) when inland or on
    /// failure, rather than surfacing an error.
    func weekTidesByDay(
        near location: CLLocation,
        on date: Date = .now,
        days: Int = 7,
        calendar: Calendar = .current
    ) async -> [Date: [TideEvent]] {
        do {
            if stations.isEmpty {
                stations = try await Self.loadStations()
            }
            guard let nearest = nearestStation(to: location) else { return [:] }
            let miles = location.distance(from: CLLocation(
                latitude: nearest.latitude, longitude: nearest.longitude
            )) / 1609.34
            guard miles <= maxStationDistanceMiles else { return [:] }

            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: days, to: start)
                ?? start.addingTimeInterval(Double(days) * 86_400)
            let points = try await Self.fetchHiLoRange(
                stationId: nearest.id,
                from: start,
                to: end
            )
            return Self.eventsByDay(points.compactMap(\.event), calendar: calendar)
        } catch {
            return [:]
        }
    }

    func hasData(
        for location: CLLocation,
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        loadedLocationKey == Self.locationKey(location)
            && station != nil
            && loadedCoverage.map {
                Self.coversFullDay($0, containing: date, calendar: calendar)
            } == true
            && Self.hasPredictions(
                events: allEvents,
                samples: allSamples,
                on: date,
                calendar: calendar
            )
    }

    /// Retained high/low predictions for an arbitrary forecast-local day.
    func events(on date: Date, calendar: Calendar) -> [TideEvent] {
        Self.events(in: allEvents, on: date, calendar: calendar)
    }

    /// Retained hourly predictions for an arbitrary forecast-local day.
    func samples(on date: Date, calendar: Calendar) -> [TideSample] {
        Self.samples(in: allSamples, on: date, calendar: calendar)
    }

    /// A successful load that found no station in range — a real answer, not an error.
    private func finishInland(key: String) {
        clear()
        lastKey = key
        isLoading = false
    }

    private func clear() {
        // A cleared/failed request must never remain a cache hit. Inland loads
        // deliberately restore `lastKey` in `finishInland` after clearing.
        lastKey = nil
        events = []
        allEvents = []
        samples = []
        allSamples = []
        station = nil
        distanceMiles = nil
        loadedLocationKey = nil
        loadedCoverage = nil
    }

    private func nearestStation(to location: CLLocation) -> TideStation? {
        stations.min { a, b in
            let da = location.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude))
            let db = location.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            return da < db
        }
    }

    // MARK: - Networking

    /// Loads the station catalog from the disk cache when fresh (it changes a
    /// few times a year at most), otherwise downloads and caches it. Runs off
    /// the main actor — the ~1 MB decode caused a visible hitch.
    nonisolated private static func loadStations() async throws -> [TideStation] {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tide-stations.json")
        let maxAge: TimeInterval = 30 * 24 * 3600

        if let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modified = attributes[.modificationDate] as? Date,
           Date.now.timeIntervalSince(modified) < maxAge,
           let data = try? Data(contentsOf: cacheURL),
           let cached = try? decodeStations(data),
           !cached.isEmpty {
            return cached
        }

        let url = URL(string: "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try HTTPStatusError.validate(response)
        let stations = try decodeStations(data)
        // Never persist an empty catalog — it would suppress tides for 30 days.
        guard !stations.isEmpty else {
            throw NOAADataError(message: "No tide stations returned.")
        }
        try? data.write(to: cacheURL, options: .atomic)
        return stations
    }

    nonisolated private static func decodeStations(_ data: Data) throws -> [TideStation] {
        try JSONDecoder().decode(StationListResponse.self, from: data).stations.map {
            TideStation(id: $0.id, name: $0.name, latitude: $0.lat, longitude: $0.lng)
        }
    }

    nonisolated private static func fetchPredictions(
        stationId: String,
        requestRange: TideRequestDateRange,
        interval: String
    ) async throws -> [TidePoint] {
        var components = URLComponents(string: "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter")!
        components.queryItems = [
            URLQueryItem(name: "product", value: "predictions"),
            URLQueryItem(name: "application", value: "BiteCast"),
            URLQueryItem(name: "station", value: stationId),
            URLQueryItem(name: "begin_date", value: requestRange.beginDate),
            URLQueryItem(name: "end_date", value: requestRange.endDate),
            URLQueryItem(name: "datum", value: "MLLW"),
            URLQueryItem(name: "units", value: "english"),
            URLQueryItem(name: "time_zone", value: "gmt"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "interval", value: interval)
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try HTTPStatusError.validate(response)
        return try parsePredictions(data)
    }

    /// High/low predictions across an arbitrary date range (used by the trip
    /// planner's week fetch), in GMT.
    nonisolated private static func fetchHiLoRange(
        stationId: String, from: Date, to: Date
    ) async throws -> [TidePoint] {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyyMMdd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(identifier: "GMT")

        var components = URLComponents(string: "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter")!
        components.queryItems = [
            URLQueryItem(name: "product", value: "predictions"),
            URLQueryItem(name: "application", value: "BiteCast"),
            URLQueryItem(name: "station", value: stationId),
            URLQueryItem(name: "begin_date", value: dayFormatter.string(from: from)),
            URLQueryItem(name: "end_date", value: dayFormatter.string(from: to)),
            URLQueryItem(name: "datum", value: "MLLW"),
            URLQueryItem(name: "units", value: "english"),
            URLQueryItem(name: "time_zone", value: "gmt"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "interval", value: "hilo")
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try HTTPStatusError.validate(response)
        return try parsePredictions(data)
    }

    /// Parses a NOAA predictions payload. Internal (not private) so the GMT
    /// date handling stays under test.
    nonisolated static func parsePredictions(_ data: Data) throws -> [TidePoint] {
        let decoded = try JSONDecoder().decode(PredictionsResponse.self, from: data)
        if let message = decoded.error?.message {
            throw NOAADataError(message: message)
        }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = TimeZone(identifier: "GMT")
        return (decoded.predictions ?? []).compactMap { dto in
            guard let time = timeFormatter.date(from: dto.t),
                  let value = Double(dto.v) else { return nil }
            let kind: TideEvent.Kind? = switch dto.type {
            case "H": .high
            case "L": .low
            default: nil
            }
            return TidePoint(time: time, heightFeet: value, kind: kind)
        }
    }

    /// Pure day slice used by both the compatibility state and arbitrary-day UI.
    nonisolated static func events(
        in events: [TideEvent],
        on date: Date,
        calendar: Calendar
    ) -> [TideEvent] {
        events.filter { calendar.isDate($0.time, inSameDayAs: date) }
    }

    /// Pure day slice used by both the compatibility state and arbitrary-day UI.
    nonisolated static func samples(
        in samples: [TideSample],
        on date: Date,
        calendar: Calendar
    ) -> [TideSample] {
        samples.filter { calendar.isDate($0.time, inSameDayAs: date) }
    }

    nonisolated static func hasPredictions(
        events: [TideEvent],
        samples: [TideSample],
        on date: Date,
        calendar: Calendar
    ) -> Bool {
        events.contains { calendar.isDate($0.time, inSameDayAs: date) }
            || samples.contains { calendar.isDate($0.time, inSameDayAs: date) }
    }

    /// True only when NOAA's absolute response interval contains the complete
    /// forecast-local day, not merely a GMT-padded fragment of that day.
    nonisolated static func coversFullDay(
        _ coverage: Range<Date>,
        containing date: Date,
        calendar: Calendar
    ) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        return coverage.lowerBound <= dayStart && coverage.upperBound >= nextDay
    }

    /// Groups retained or freshly fetched events by forecast-local day.
    nonisolated static func eventsByDay(
        _ events: [TideEvent],
        calendar: Calendar
    ) -> [Date: [TideEvent]] {
        Dictionary(grouping: events) {
            calendar.startOfDay(for: $0.time)
        }
    }

    /// Converts a forecast-local yesterday–tomorrow window to inclusive GMT
    /// calendar days for NOAA's date-only request parameters.
    nonisolated static func requestDateRange(
        containing date: Date,
        calendar: Calendar
    ) -> TideRequestDateRange {
        let selectedDay = calendar.startOfDay(for: date)
        let lowerBound = calendar.date(byAdding: .day, value: -1, to: selectedDay)
            ?? selectedDay.addingTimeInterval(-86_400)
        let upperExclusive = calendar.date(byAdding: .day, value: 2, to: selectedDay)
            ?? selectedDay.addingTimeInterval(2 * 86_400)
        let inclusiveUpperBound = upperExclusive.addingTimeInterval(-1)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        var gmtCalendar = Calendar(identifier: .gregorian)
        gmtCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let coverageStart = gmtCalendar.startOfDay(for: lowerBound)
        let coverageEndDay = gmtCalendar.startOfDay(for: inclusiveUpperBound)
        let coverageEnd = gmtCalendar.date(
            byAdding: .day,
            value: 1,
            to: coverageEndDay
        ) ?? coverageEndDay.addingTimeInterval(86_400)
        return TideRequestDateRange(
            beginDate: formatter.string(from: lowerBound),
            endDate: formatter.string(from: inclusiveUpperBound),
            coverage: coverageStart..<coverageEnd
        )
    }

    nonisolated static func dataKey(
        _ location: CLLocation,
        date: Date,
        calendar: Calendar = .current
    ) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let dayKey = String(
            format: "%04d%02d%02d",
            day.year ?? 0,
            day.month ?? 0,
            day.day ?? 0
        )
        return "\(locationKey(location))-\(calendar.timeZone.identifier)-\(dayKey)"
    }

    nonisolated private static func locationKey(_ location: CLLocation) -> String {
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        return "\(lat),\(lon)"
    }
}

// MARK: - NOAA payloads
// File scope so the nonisolated parsing helpers can decode them without
// inheriting the service's main-actor isolation.

private struct StationListResponse: Decodable {
    let stations: [StationDTO]

    struct StationDTO: Decodable {
        let id: String
        let name: String
        let lat: Double
        let lng: Double
    }
}

private struct PredictionsResponse: Decodable {
    let predictions: [PredictionDTO]?
    let error: ErrorDTO?

    struct PredictionDTO: Decodable {
        let t: String     // "yyyy-MM-dd HH:mm" (GMT — we request time_zone=gmt)
        let v: String     // height in feet
        let type: String? // "H" or "L" when interval=hilo
    }

    struct ErrorDTO: Decodable {
        let message: String?
    }
}
