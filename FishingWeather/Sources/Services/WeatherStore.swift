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

    private func cacheKey(for location: CLLocation) -> String {
        let c = location.coordinate
        return GeoTile.key(lat: c.latitude, lon: c.longitude)
    }

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

            // Persist a lightweight snapshot to disk for offline charts/pressure.
            let samples = hourly.samples()
            let pressure = PressureReading.analyze(current: current, hourly: hourly.forecast, now: .now)
            let key = cacheKey(for: location)
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
                let file = base.appendingPathComponent("\(key).json")
                try? data.write(to: file, options: .atomic)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

