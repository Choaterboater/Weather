import CoreLocation
import Foundation
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
    /// Cache key for the payload currently held in `current`/`hourly`/`daily`.
    /// Views use this to refuse rendering data for a different active location.
    private(set) var loadedKey: String?

    private var loadID = 0
    private var lastFetch: (key: String, date: Date)?
    /// Forecasts don't move fast; re-fetching the full 4-dataset bundle on
    /// every spot flip burns WeatherKit quota and shows spinners for nothing.
    private let cacheTTL: TimeInterval = 15 * 60

    /// The assembled fishing facts — derived state shared by several tabs.
    var conditions: FishingConditions? {
        guard let current, let hourly, let today = daily?.forecast.first else { return nil }
        return FishingConditions.make(current: current, hourly: hourly, today: today)
    }

    /// True when held weather matches `location`'s cache key.
    func hasData(for location: CLLocation) -> Bool {
        loadedKey == Self.cacheKey(for: location) && current != nil
    }

    func load(for location: CLLocation, force: Bool = false) async {
        let key = Self.cacheKey(for: location)
        // Bump first so a cache hit still supersedes an in-flight fetch for
        // another location that might complete later.
        loadID += 1
        let id = loadID

        if !force, current != nil, let lastFetch,
           lastFetch.key == key, Date.now.timeIntervalSince(lastFetch.date) < cacheTTL {
            isLoading = false
            return
        }
        // Drop prior-location payloads so the UI can't present them as current.
        if loadedKey != key {
            current = nil
            hourly = nil
            daily = nil
            alerts = []
            loadedKey = nil
        }
        isLoading = true
        errorMessage = nil

        do {
            // Start the hourly window 6h back so the pressure trend has a real
            // baseline; every consumer of `hourly` filters to future hours.
            let now = Date.now
            let (current, hourly, daily, alerts) = try await service.weather(
                for: location,
                including: .current,
                .hourly(startDate: now.addingTimeInterval(-6 * 3600),
                        endDate: now.addingTimeInterval(26 * 3600)),
                .daily, .alerts
            )
            // A newer load superseded this one; its writes win, not ours.
            guard id == loadID else { return }
            self.current = current
            self.hourly = hourly
            self.daily = daily
            self.alerts = alerts ?? []
            loadedKey = key
            lastFetch = (key, .now)
            isLoading = false

            // Persist a lightweight snapshot to disk for offline charts/pressure.
            // WeatherSnapshots keys by GeoTile (0.1 degree, ~11 km) — deliberately
            // coarser than the 0.01-degree TTL cache key above; do not unify the two.
            // Persist the full window (incl. the past hours we requested for
            // pressure trend) — `samples()` alone drops history and leaves
            // offline charts without a baseline.
            WeatherSnapshots.save(
                samples: hourly.allSamples(),
                pressure: PressureReading.analyze(current: current, hourly: hourly.forecast, now: .now),
                for: location
            )
        } catch {
            guard id == loadID else { return }
            isLoading = false
            // A cancelled fetch (spot switched mid-flight) is not an error state.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.localizedDescription
        }
    }

    static func cacheKey(for location: CLLocation) -> String {
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        return "\(lat),\(lon)"
    }
}
