import CoreLocation
import Foundation
import os

/// Versioned, provider-neutral weather snapshot storage keyed by a 0.1-degree
/// geographic tile. Actor isolation keeps file access and schema migration safe
/// when live and fallback providers run concurrently.
actor WeatherSnapshots {
    private struct Envelope: Codable {
        let version: Int
        let snapshot: WeatherSnapshot
    }

    private struct EnvelopeHeader: Decodable {
        let version: Int
    }

    private static let currentVersion = 1
    private static let logger = Logger(
        subsystem: "app.choatelabs.bitecast",
        category: "WeatherSnapshots"
    )

    private let directory: URL
    private let fileManager: FileManager

    init(
        directory: URL = WeatherSnapshots.defaultDirectory(),
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.fileManager = fileManager
    }

    func save(_ snapshot: WeatherSnapshot) throws {
        let envelope = Envelope(
            version: Self.currentVersion,
            snapshot: snapshot
        )
        let data = try JSONEncoder().encode(envelope)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(
            to: fileURL(
                latitude: snapshot.coordinate.latitude,
                longitude: snapshot.coordinate.longitude
            ),
            options: .atomic
        )
    }

    /// Loads the exact persisted snapshot, including its original provenance.
    /// Callers that expose cache provenance adapt it after this boundary.
    func load(for location: CLLocation) -> WeatherSnapshot? {
        let url = fileURL(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let header = try decoder.decode(EnvelopeHeader.self, from: data)
            guard header.version == Self.currentVersion else {
                backupInvalidFile(at: url)
                return nil
            }
            return try decoder.decode(Envelope.self, from: data).snapshot
        } catch {
            Self.logger.error(
                "snapshot decode failed for \(url.lastPathComponent): \(error.localizedDescription)"
            )
            backupInvalidFile(at: url)
            return nil
        }
    }

    nonisolated private static func defaultDirectory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WeatherSnapshots", isDirectory: true)
    }

    private func fileURL(latitude: Double, longitude: Double) -> URL {
        let key = GeoTile.key(lat: latitude, lon: longitude)
        return directory.appendingPathComponent("\(key).json")
    }

    private func backupInvalidFile(at url: URL) {
        let stem = url.deletingPathExtension().lastPathComponent
        let backup = directory.appendingPathComponent(
            "\(stem).invalid-\(UUID().uuidString).json"
        )
        do {
            try fileManager.moveItem(at: url, to: backup)
        } catch {
            Self.logger.error(
                "snapshot backup failed for \(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }
}

/// Final provider in the fallback chain. It deliberately preserves the
/// original fetch time while identifying the delivery source as the cache.
struct CachedWeatherProvider: WeatherProvider {
    let cache: WeatherSnapshots

    func forecast(for location: CLLocation) async throws -> WeatherSnapshot {
        guard let persisted = await cache.load(for: location) else {
            throw WeatherProviderError.serviceUnavailable
        }

        let origin = persisted.provenance.attribution
            ?? persisted.provenance.source.attributionName
        return WeatherSnapshot(
            coordinate: persisted.coordinate,
            timeZoneIdentifier: persisted.timeZoneIdentifier,
            current: persisted.current,
            hourly: persisted.hourly,
            daily: persisted.daily,
            alerts: persisted.alerts,
            astronomy: persisted.astronomy,
            provenance: WeatherProvenance(
                source: .cache,
                fetchedAt: persisted.provenance.fetchedAt,
                isFallback: true,
                attribution: "Cached from \(origin)"
            )
        )
    }
}

private extension WeatherSource {
    var attributionName: String {
        switch self {
        case .weatherKit: "Apple Weather"
        case .nws: "National Weather Service"
        case .cache: "a previous weather source"
        }
    }
}
