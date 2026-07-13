import CoreLocation
import Foundation
import os

/// Versioned, provider-neutral weather snapshot storage keyed by a 0.1-degree
/// geographic tile. Actor isolation keeps file access and schema migration safe
/// when live and fallback providers run concurrently.
actor WeatherSnapshots {
    private enum SnapshotFileError: LocalizedError {
        case unsupportedVersion(Int)
        case futureFetchTime

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                "Unsupported snapshot version \(version)"
            case .futureFetchTime:
                "Snapshot fetch time is in the future"
            }
        }
    }

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
    private let now: @Sendable () -> Date

    init(
        directory: URL = WeatherSnapshots.defaultDirectory(),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.now = now
    }

    func save(_ snapshot: WeatherSnapshot) throws {
        let saveDate = now()
        guard snapshot.provenance.fetchedAt <= saveDate else {
            throw SnapshotFileError.futureFetchTime
        }

        let url = fileURL(
            latitude: snapshot.coordinate.latitude,
            longitude: snapshot.coordinate.longitude
        )
        if fileManager.fileExists(atPath: url.path) {
            let existing: WeatherSnapshot?
            do {
                existing = try decodedSnapshot(at: url)
            } catch {
                Self.logger.error(
                    "snapshot decode failed before save for \(url.lastPathComponent): \(error.localizedDescription)"
                )
                // A failed move must abort the save so the only copy of the
                // invalid or unknown-version bytes is never overwritten.
                try backupInvalidFile(at: url)
                existing = nil
            }

            if let existing {
                if existing.provenance.fetchedAt > saveDate {
                    Self.logger.error(
                        "future snapshot quarantined before save for \(url.lastPathComponent)"
                    )
                    try backupInvalidFile(at: url)
                } else if existing.provenance.fetchedAt >= snapshot.provenance.fetchedAt {
                    // Equal timestamps keep the existing envelope. This makes
                    // retries idempotent and gives actor-serialized writers a
                    // deterministic winner.
                    return
                }
            }
        }

        let envelope = Envelope(
            version: Self.currentVersion,
            snapshot: snapshot
        )
        let data = try JSONEncoder().encode(envelope)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
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
            return try decodedSnapshot(at: url)
        } catch {
            Self.logger.error(
                "snapshot decode failed for \(url.lastPathComponent): \(error.localizedDescription)"
            )
            do {
                try backupInvalidFile(at: url)
            } catch {
                Self.logger.error(
                    "snapshot backup failed for \(url.lastPathComponent): \(error.localizedDescription)"
                )
            }
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

    private func decodedSnapshot(at url: URL) throws -> WeatherSnapshot {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let header = try decoder.decode(EnvelopeHeader.self, from: data)
        guard header.version == Self.currentVersion else {
            throw SnapshotFileError.unsupportedVersion(header.version)
        }
        return try decoder.decode(Envelope.self, from: data).snapshot
    }

    private func backupInvalidFile(at url: URL) throws {
        let stem = url.deletingPathExtension().lastPathComponent
        let backup = directory.appendingPathComponent(
            "\(stem).invalid-\(UUID().uuidString).json"
        )
        try fileManager.moveItem(at: url, to: backup)
    }
}

/// Final provider in the fallback chain. It deliberately preserves the
/// original fetch time while identifying the delivery source as the cache.
struct CachedWeatherProvider: WeatherProvider {
    typealias Clock = @Sendable () -> Date

    static let defaultMaxAge: TimeInterval = 24 * 3_600

    let cache: WeatherSnapshots
    let maxAge: TimeInterval
    private let now: Clock

    init(
        cache: WeatherSnapshots,
        maxAge: TimeInterval = Self.defaultMaxAge,
        now: @escaping Clock = { .now }
    ) {
        self.cache = cache
        self.maxAge = maxAge
        self.now = now
    }

    func forecast(for location: CLLocation) async throws -> WeatherSnapshot {
        guard let persisted = await cache.load(for: location) else {
            throw WeatherProviderError.serviceUnavailable
        }

        let age = now().timeIntervalSince(persisted.provenance.fetchedAt)
        guard maxAge.isFinite,
              maxAge >= 0,
              age >= 0,
              age <= maxAge else {
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
