import CoreLocation
import Foundation
import Observation
import WeatherKit

/// Fetches the extended forecast for the Weekly Trip Planner and feeds it to
/// `TripPlanner`. Kept separate from `WeatherStore` so the everyday dashboard
/// fetch stays lean — the planner pulls a wider hourly window on demand.
@MainActor
@Observable
final class TripForecastLoader {
    typealias Worker = @MainActor (CLLocation, Species, String) async throws -> WeekOutlook

    private(set) var outlook: WeekOutlook?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let service = WeatherService.shared
    private let worker: Worker?
    private var lastKey: String?
    private var loadID = 0

    /// Hours of hourly forecast to request — defines the high-confidence
    /// horizon. Beyond this, days score from the daily forecast (low confidence).
    private let hourlyHorizon: TimeInterval = 60 * 3600

    init(worker: Worker? = nil) {
        self.worker = worker
    }

    func load(for location: CLLocation, species: Species, locationName: String,
              tides: (CLLocation) async -> [Date: [TideEvent]] = { _ in [:] },
              force: Bool = false) async -> WeekOutlook? {
        let key = Self.requestKey(
            location: location,
            species: species,
            locationName: locationName
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
                let now = Date.now
                let (daily, hourly) = try await service.weather(
                    for: location,
                    including: .daily,
                    .hourly(startDate: now, endDate: now.addingTimeInterval(hourlyHorizon))
                )
                guard id == loadID, !Task.isCancelled else {
                    if id == loadID { isLoading = false }
                    return nil
                }

                let days: [DayForecastInput] = daily.forecast.prefix(7).map { day in
                    DayForecastInput(
                        date: day.date,
                        moonrise: day.moon.moonrise,
                        moonset: day.moon.moonset,
                        moonPhase: day.moon.phase,
                        dailyWindMph: day.wind.speed.converted(to: .milesPerHour).value
                    )
                }

                // A week of NOAA hi/lo predictions grouped by day; empty for inland
                // spots (the scorer then drops the tide factor).
                let tidesByDay = await tides(location)
                guard id == loadID, !Task.isCancelled else {
                    if id == loadID { isLoading = false }
                    return nil
                }

                result = TripPlanner.outlook(
                    days: days,
                    hourly: hourly.samples(72, now: now),
                    tidesByDay: tidesByDay,
                    species: species,
                    locationName: locationName,
                    now: now
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
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return nil }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    nonisolated static func requestKey(
        location: CLLocation,
        species: Species,
        locationName: String
    ) -> String {
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        return "\(species.rawValue)|\(lat),\(lon)|\(locationName)"
    }
}
