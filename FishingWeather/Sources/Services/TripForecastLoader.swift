import CoreLocation
import Foundation
import Observation

/// Builds a weekly outlook from the canonical snapshot already loaded for the
/// active location. No provider-specific service crosses this boundary.
@MainActor
@Observable
final class TripForecastLoader {
    typealias Worker = @MainActor (
        CLLocation,
        Species,
        String
    ) async throws -> WeekOutlook

    private(set) var outlook: WeekOutlook?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let worker: Worker?
    private var lastKey: String?
    private var loadID = 0

    init(worker: Worker? = nil) {
        self.worker = worker
    }

    func load(
        for location: CLLocation,
        species: Species,
        locationName: String,
        snapshot: WeatherSnapshot? = nil,
        tides: (CLLocation) async -> [Date: [TideEvent]] = { _ in [:] },
        force: Bool = false
    ) async -> WeekOutlook? {
        let key = Self.requestKey(
            location: location,
            species: species,
            locationName: locationName,
            snapshot: snapshot
        )
        if !force, outlook != nil, lastKey == key { return outlook }

        loadID += 1
        let id = loadID
        if lastKey != key {
            outlook = nil
            lastKey = nil
        }

        isLoading = true
        errorMessage = nil
        do {
            let result: WeekOutlook
            if let worker {
                result = try await worker(location, species, locationName)
            } else {
                guard let snapshot else {
                    throw WeatherProviderError.serviceUnavailable
                }
                let now = Date.now
                let calendar = Self.forecastCalendar(for: snapshot)
                let days = snapshot.daily.prefix(7).map(Self.dayInput)

                guard id == loadID, !Task.isCancelled else {
                    if id == loadID { isLoading = false }
                    return nil
                }

                let tidesByDay = await tides(location)
                guard id == loadID, !Task.isCancelled else {
                    if id == loadID { isLoading = false }
                    return nil
                }

                result = TripPlanner.outlook(
                    days: days,
                    hourly: snapshot.hourly,
                    tidesByDay: tidesByDay,
                    species: species,
                    locationName: locationName,
                    now: now,
                    calendar: calendar
                )
            }

            guard id == loadID, !Task.isCancelled else {
                if id == loadID { isLoading = false }
                return nil
            }

            outlook = result
            lastKey = key
            isLoading = false
            return result
        } catch {
            guard id == loadID else { return nil }
            isLoading = false
            if error is CancellationError
                || (error as? URLError)?.code == .cancelled
                || Task.isCancelled {
                return nil
            }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    nonisolated static func dayInput(
        from day: DailyWeatherPoint
    ) -> DayForecastInput {
        let astronomy = day.astronomy
        let dailyWind = day.windMetersPerSecond
            ?? day.windPeakMetersPerSecond
        return DayForecastInput(
            date: day.date,
            moonrise: astronomy?.moonrise,
            moonset: astronomy?.moonset,
            moonPhase: LunarPhase(
                cycleFraction: astronomy?.moonPhaseFraction
            ),
            dailyWindMph: dailyWind.map {
                WeatherUnits.milesPerHour(metersPerSecond: $0)
            }
        )
    }

    nonisolated static func forecastCalendar(
        for snapshot: WeatherSnapshot?
    ) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot
            .flatMap { TimeZone(identifier: $0.timeZoneIdentifier) }
            ?? .gmt
        return calendar
    }

    nonisolated static func requestKey(
        location: CLLocation,
        species: Species,
        locationName: String,
        snapshot: WeatherSnapshot? = nil
    ) -> String {
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        let revision = snapshot.map {
            "\($0.provenance.source.rawValue):\($0.provenance.fetchedAt.timeIntervalSinceReferenceDate)"
        } ?? "none"
        return "\(species.rawValue)|\(lat),\(lon)|\(locationName)|weather:\(revision)"
    }
}
