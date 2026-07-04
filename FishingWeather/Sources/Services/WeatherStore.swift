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

    func load(for location: CLLocation, force: Bool = false) async {
        let key = Self.cacheKey(for: location)
        if !force, current != nil, let lastFetch,
           lastFetch.key == key, Date.now.timeIntervalSince(lastFetch.date) < cacheTTL {
            return
        }

        loadID += 1
        let id = loadID
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
            lastFetch = (key, .now)
            isLoading = false

            // Persist a lightweight snapshot to disk for offline charts/pressure.
            // Keyed by GeoTile (0.1 degree, ~11 km) — deliberately coarser than the
            // 0.01-degree TTL cache key above; do not unify the two.
            let samples = hourly.samples()
            let pressure = PressureReading.analyze(current: current, hourly: hourly.forecast, now: .now)
            let snapshotKey = GeoTile.key(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
            // Build a JSON entry compatible with WeatherSnapshots
            struct SnapshotHour: Codable { let date: Date; let temperature: Double; let pressureHPa: Double; let precipChance: Double }
            struct SnapshotPressure: Codable { let pressureHPa: Double; let tendency: String; let changePerHour: Double? }
            struct SnapshotEntry: Codable { let timestamp: Date; let samples: [SnapshotHour]; let pressure: SnapshotPressure }
            let entry = SnapshotEntry(
                timestamp: .now,
                samples: samples.map { SnapshotHour(date: $0.date, temperature: $0.temperature, pressureHPa: $0.pressureHPa, precipChance: $0.precipChance) },
                pressure: SnapshotPressure(pressureHPa: pressure.pressure.converted(to: .hectopascals).value, tendency: pressure.tendency.label.lowercased(), changePerHour: pressure.changePerHour)
            )
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(entry) {
                let fm = FileManager.default
                let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("WeatherSnapshots", isDirectory: true)
                try? fm.createDirectory(at: base, withIntermediateDirectories: true)
                let file = base.appendingPathComponent("\(snapshotKey).json")
                try? data.write(to: file, options: .atomic)
            }
        } catch {
            guard id == loadID else { return }
            isLoading = false
            // A cancelled fetch (spot switched mid-flight) is not an error state.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.localizedDescription
        }
    }

    private static func cacheKey(for location: CLLocation) -> String {
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        return "\(lat),\(lon)"
    }
}

