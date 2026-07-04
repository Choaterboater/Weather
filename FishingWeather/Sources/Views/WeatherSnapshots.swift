import Foundation
import CoreLocation
import WeatherKit

/// Offline snapshot helpers for weather data. Reads lightweight JSON snapshots
/// so the UI can render charts and pressure when live data is unavailable.
struct WeatherSnapshots {
    private struct SnapshotHour: Codable {
        let date: Date
        let temperature: Double
        let pressureHPa: Double
        let precipChance: Double
    }

    private struct SnapshotPressure: Codable {
        let pressureHPa: Double
        let tendency: String
        let changePerHour: Double?
    }

    private struct SnapshotEntry: Codable {
        let timestamp: Date
        let samples: [SnapshotHour]
        let pressure: SnapshotPressure
    }

    private static func snapshotURL(forKey key: String) -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WeatherSnapshots", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("\(key).json")
    }

    private static func tileKey(for location: CLLocation) -> String {
        let c = location.coordinate
        return GeoTile.key(lat: c.latitude, lon: c.longitude)
    }

    private static func loadSnapshot(forKey key: String) -> SnapshotEntry? {
        let url = snapshotURL(forKey: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SnapshotEntry.self, from: data)
    }

    static func cachedSamples(for location: CLLocation) -> [HourSample] {
        let key = tileKey(for: location)
        guard let snap = loadSnapshot(forKey: key) else { return [] }
        return snap.samples.map { HourSample(date: $0.date, temperature: $0.temperature, pressureHPa: $0.pressureHPa, precipChance: $0.precipChance) }
    }

    static func cachedPressure(for location: CLLocation) -> PressureReading? {
        let key = tileKey(for: location)
        guard let snap = loadSnapshot(forKey: key) else { return nil }
        let tendency: PressureTendency
        switch snap.pressure.tendency.lowercased() {
        case "rising": tendency = .rising
        case "falling": tendency = .falling
        default: tendency = .steady
        }
        let measurement = Measurement(value: snap.pressure.pressureHPa, unit: UnitPressure.hectopascals)
        return PressureReading(pressure: measurement, tendency: tendency, changePerHour: snap.pressure.changePerHour)
    }
}
