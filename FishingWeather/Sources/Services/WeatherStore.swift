import CoreLocation
import Observation
import WeatherKit

/// Loads weather for a location from WeatherKit and holds it for the UI.
/// Named `WeatherStore` to avoid colliding with `WeatherKit.WeatherService`.
@MainActor
@Observable
final class WeatherStore {
    private let service = WeatherService.shared

    var current: CurrentWeather?
    var hourly: Forecast<HourWeather>?
    var daily: Forecast<DayWeather>?
    var alerts: [WeatherAlert] = []

    var isLoading = false
    var errorMessage: String?

    func load(for location: CLLocation) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let (current, hourly, daily, alerts) = try await service.weather(
                for: location,
                including: .current, .hourly, .daily, .alerts
            )
            self.current = current
            self.hourly = hourly
            self.daily = daily
            self.alerts = alerts ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
