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
    private(set) var outlook: WeekOutlook?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let service = WeatherService.shared
    private var lastKey: String?

    /// Hours of hourly forecast to request — defines the high-confidence
    /// horizon. Beyond this, days score from the daily forecast (low confidence).
    private let hourlyHorizon: TimeInterval = 60 * 3600

    func load(for location: CLLocation, species: Species, locationName: String,
              force: Bool = false) async {
        let key = Self.cacheKey(location: location, species: species)
        if !force, outlook != nil, lastKey == key { return }

        isLoading = true
        errorMessage = nil
        do {
            let now = Date.now
            let (daily, hourly) = try await service.weather(
                for: location,
                including: .daily,
                .hourly(startDate: now, endDate: now.addingTimeInterval(hourlyHorizon))
            )

            let days: [DayForecastInput] = daily.forecast.prefix(7).map { day in
                DayForecastInput(
                    date: day.date,
                    moonrise: day.moon.moonrise,
                    moonset: day.moon.moonset,
                    moonPhase: day.moon.phase,
                    dailyWindMph: day.wind.speed.converted(to: .milesPerHour).value
                )
            }

            let result = TripPlanner.outlook(
                days: days,
                hourly: hourly.samples(72, now: now),
                // Tides omitted in v1 — freshwater scores without them and the
                // scorer degrades gracefully for saltwater. A week of NOAA tide
                // predictions is a planned follow-up.
                tidesByDay: [:],
                species: species,
                locationName: locationName,
                now: now
            )

            outlook = result
            lastKey = key
            isLoading = false
        } catch {
            isLoading = false
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.localizedDescription
        }
    }

    private static func cacheKey(location: CLLocation, species: Species) -> String {
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        return "\(species.rawValue)|\(lat),\(lon)"
    }
}
