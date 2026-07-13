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
        case expiredSnapshot
        case invalidAttribution

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                "Unsupported snapshot version \(version)"
            case .futureFetchTime:
                "Snapshot fetch time is in the future"
            case .expiredSnapshot:
                "Snapshot is already expired"
            case .invalidAttribution:
                "Snapshot provider attribution is invalid"
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

    private static let currentVersion = 2
    private static let logger = Logger(
        subsystem: "app.choatelabs.bitecast",
        category: "WeatherSnapshots"
    )

    private let directory: URL
    private let legacyDirectory: URL?
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    init(
        directory: URL? = nil,
        legacyDirectory: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        let usesDefaultDirectory = directory == nil
        self.directory = directory ?? WeatherSnapshots.defaultDirectory()
        self.legacyDirectory = legacyDirectory
            ?? (usesDefaultDirectory ? WeatherSnapshots.legacyDirectory() : nil)
        self.fileManager = fileManager
        self.now = now
    }

    func save(_ snapshot: WeatherSnapshot) throws {
        purgeLegacyDirectory()
        try purgeInvalidEntries()
        let saveDate = now()
        guard snapshot.provenance.fetchedAt.timeIntervalSinceReferenceDate.isFinite,
              snapshot.provenance.fetchedAt <= saveDate else {
            throw SnapshotFileError.futureFetchTime
        }
        guard snapshot.provenance.expiresAt.timeIntervalSinceReferenceDate.isFinite,
              snapshot.provenance.expiresAt > saveDate else {
            throw SnapshotFileError.expiredSnapshot
        }
        guard Self.hasRequiredAttribution(snapshot) else {
            throw SnapshotFileError.invalidAttribution
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
                // Weather snapshots are temporary, replaceable cache bytes.
                // Unknown or corrupt entries are purged rather than retained
                // as recovery backups.
                try fileManager.removeItem(at: url)
                existing = nil
            }

            if let existing {
                if !existing.provenance.isValid(at: saveDate) {
                    Self.logger.error(
                        "invalid or expired snapshot purged before save for \(url.lastPathComponent)"
                    )
                    try fileManager.removeItem(at: url)
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
        try prepareDirectory()
        try data.write(to: url, options: .atomic)
    }

    /// Loads the exact persisted snapshot, including its original provenance.
    /// Callers that expose cache provenance adapt it after this boundary.
    func load(for location: CLLocation) -> WeatherSnapshot? {
        purgeLegacyDirectory()
        do {
            try purgeInvalidEntries()
        } catch {
            Self.logger.error(
                "weather cache sweep failed: \(error.localizedDescription)"
            )
        }
        let url = fileURL(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let snapshot = try decodedSnapshot(at: url)
            guard snapshot.provenance.isValid(at: now()) else {
                try fileManager.removeItem(at: url)
                return nil
            }
            return snapshot
        } catch {
            Self.logger.error(
                "snapshot decode failed for \(url.lastPathComponent): \(error.localizedDescription)"
            )
            do {
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
            } catch {
                Self.logger.error(
                    "snapshot purge failed for \(url.lastPathComponent): \(error.localizedDescription)"
                )
            }
            return nil
        }
    }

    nonisolated static func defaultDirectory() -> URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BiteCast", isDirectory: true)
            .appendingPathComponent("WeatherSnapshots", isDirectory: true)
    }

    nonisolated private static func legacyDirectory() -> URL {
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
        let snapshot = try decoder.decode(Envelope.self, from: data).snapshot
        guard Self.hasRequiredAttribution(snapshot) else {
            throw SnapshotFileError.invalidAttribution
        }
        return snapshot
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(values)
    }

    private func purgeLegacyDirectory() {
        guard let legacyDirectory,
              fileManager.fileExists(atPath: legacyDirectory.path)
        else { return }
        do {
            try fileManager.removeItem(at: legacyDirectory)
        } catch {
            Self.logger.error(
                "legacy weather cache purge failed: \(error.localizedDescription)"
            )
        }
    }

    private func purgeInvalidEntries() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let referenceDate = now()
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for entry in entries {
            let shouldKeep: Bool
            if entry.pathExtension == "json" {
                do {
                    shouldKeep = try decodedSnapshot(at: entry)
                        .provenance.isValid(at: referenceDate)
                } catch {
                    shouldKeep = false
                }
            } else {
                shouldKeep = false
            }
            if !shouldKeep {
                try fileManager.removeItem(at: entry)
            }
        }
    }

    private nonisolated static func hasRequiredAttribution(
        _ snapshot: WeatherSnapshot
    ) -> Bool {
        switch snapshot.provenance.source {
        case .weatherKit:
            guard let attribution = snapshot.provenance.providerAttribution,
                  attribution.providerKind == .appleWeather,
                  attribution.hasRequiredSecureMetadata else { return false }
            return WeatherAttributionMarkLoader.hasUsableAppleMarks(attribution)
        case .nws:
            guard let attribution = snapshot.provenance.providerAttribution else {
                return false
            }
            return attribution.providerKind == .nationalWeatherService
                && attribution.hasRequiredSecureMetadata
        case .cache:
            return false
        }
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

        let referenceDate = now()
        let age = referenceDate.timeIntervalSince(persisted.provenance.fetchedAt)
        guard maxAge.isFinite,
              maxAge >= 0,
              age >= 0,
              age <= maxAge,
              persisted.provenance.isValid(at: referenceDate) else {
            throw WeatherProviderError.serviceUnavailable
        }

        switch persisted.provenance.source {
        case .weatherKit:
            guard let providerAttribution = persisted.provenance.providerAttribution,
                  providerAttribution.providerKind == .appleWeather,
                  providerAttribution.hasRequiredSecureMetadata,
                  WeatherAttributionMarkLoader.hasUsableAppleMarks(
                      providerAttribution
                  ) else {
                throw WeatherProviderError.serviceUnavailable
            }
        case .nws:
            guard let providerAttribution = persisted.provenance.providerAttribution,
                  providerAttribution.providerKind == .nationalWeatherService,
                  providerAttribution.hasRequiredSecureMetadata else {
                throw WeatherProviderError.serviceUnavailable
            }
        case .cache:
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
                attribution: "Cached from \(origin)",
                providerAttribution: persisted.provenance.providerAttribution,
                expiresAt: persisted.provenance.expiresAt
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
