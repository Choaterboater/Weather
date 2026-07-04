import CoreLocation
import Foundation
import os

/// Single owner of the offline weather snapshot schema.
/// `WeatherStore` writes after every successful fetch; views read when live
/// WeatherKit data is unavailable. Keyed by GeoTile (0.1 degree, ~11 km).
@MainActor
enum WeatherSnapshots {
    // MARK: Schema — private; this file is its only home

    private struct Hour: Codable {
        let date: Date
        let temperature: Double
        let pressureHPa: Double
        let precipChance: Double
        // Optional so snapshots written before wind existed still decode.
        let windSpeedMph: Double?
        let windGustMph: Double?
    }

    private struct Pressure: Codable {
        let pressureHPa: Double
        let tendency: String
        let changePerHour: Double?
    }

    private struct Entry: Codable {
        let timestamp: Date
        let samples: [Hour]
        let pressure: Pressure
    }

    private static let logger = Logger(subsystem: "app.choatelabs.bitecast",
                                       category: "WeatherSnapshots")

    /// Overridable so tests can point at a temp directory.
    static var baseDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("WeatherSnapshots", isDirectory: true)

    // MARK: Write — called by WeatherStore.load on success

    static func save(samples: [HourSample], pressure: PressureReading,
                     for location: CLLocation, timestamp: Date = .now) {
        let entry = Entry(
            timestamp: timestamp,
            samples: samples.map {
                Hour(date: $0.date, temperature: $0.temperature,
                     pressureHPa: $0.pressureHPa, precipChance: $0.precipChance,
                     windSpeedMph: $0.windSpeedMph, windGustMph: $0.windGustMph)
            },
            pressure: Pressure(
                pressureHPa: pressure.pressure.converted(to: .hectopascals).value,
                tendency: pressure.tendency.label.lowercased(),
                changePerHour: pressure.changePerHour
            )
        )
        let key = tileKey(for: location)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entry)
            try FileManager.default.createDirectory(at: baseDirectory,
                                                    withIntermediateDirectories: true)
            try data.write(to: fileURL(forKey: key), options: .atomic)
        } catch {
            logger.error("snapshot write failed for \(key): \(error.localizedDescription)")
        }
    }

    // MARK: Read — called by FishingView (and future offline surfaces)

    static func cachedSamples(for location: CLLocation) -> [HourSample] {
        guard let entry = loadEntry(for: location) else { return [] }
        return entry.samples.map {
            HourSample(date: $0.date, temperature: $0.temperature,
                       pressureHPa: $0.pressureHPa, precipChance: $0.precipChance,
                       windSpeedMph: $0.windSpeedMph ?? 0, windGustMph: $0.windGustMph)
        }
    }

    static func cachedPressure(for location: CLLocation) -> PressureReading? {
        guard let entry = loadEntry(for: location) else { return nil }
        let tendency: PressureTendency = switch entry.pressure.tendency.lowercased() {
        case "rising": .rising
        case "falling": .falling
        default: .steady
        }
        return PressureReading(
            pressure: Measurement(value: entry.pressure.pressureHPa, unit: UnitPressure.hectopascals),
            tendency: tendency,
            changePerHour: entry.pressure.changePerHour
        )
    }

    /// When the snapshot was written — lets the UI caption "cached from ...".
    static func cachedTimestamp(for location: CLLocation) -> Date? {
        loadEntry(for: location)?.timestamp
    }

    // MARK: Plumbing

    private static func fileURL(forKey key: String) -> URL {
        baseDirectory.appendingPathComponent("\(key).json")
    }

    private static func tileKey(for location: CLLocation) -> String {
        let c = location.coordinate
        return GeoTile.key(lat: c.latitude, lon: c.longitude)
    }

    private static func loadEntry(for location: CLLocation) -> Entry? {
        let key = tileKey(for: location)
        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url) else { return nil }  // missing file is normal
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Entry.self, from: data)
        } catch {
            // A snapshot that exists but won't decode is a schema-drift signal.
            logger.error("snapshot decode failed for \(key): \(error.localizedDescription)")
            return nil
        }
    }
}
