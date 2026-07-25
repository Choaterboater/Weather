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

    /// Bumped to 3 when `WeatherSnapshot` gained `pressureHistory`. The version
    /// gate runs before the snapshot decode, so older envelopes are rejected
    /// cleanly rather than failing as malformed.
    private static let currentVersion = 3

    /// How long cached bytes stay on disk. This is deliberately *not* the
    /// origin provider's expiry: a snapshot that is too old to present as
    /// current is exactly the snapshot an offline angler still wants to see.
    /// `CachedWeatherProvider` decides what is servable; storage only decides
    /// what is retained.
    static let retentionWindow: TimeInterval = 24 * 3_600

    static func isRetained(
        _ provenance: WeatherProvenance,
        at date: Date,
        retentionWindow: TimeInterval = WeatherSnapshots.retentionWindow
    ) -> Bool {
        let fetchedAt = provenance.fetchedAt
        guard fetchedAt.timeIntervalSinceReferenceDate.isFinite,
              provenance.expiresAt.timeIntervalSinceReferenceDate.isFinite
        else { return false }
        let age = date.timeIntervalSince(fetchedAt)
        return age >= 0 && age <= retentionWindow
    }
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
                if !Self.isRetained(existing.provenance, at: saveDate) {
                    Self.logger.error(
                        "unretainable snapshot purged before save for \(url.lastPathComponent)"
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
            // Retention, not presentability. An expired-but-retained snapshot is
            // returned so `CachedWeatherProvider` can decide whether it is still
            // useful as an offline fallback.
            guard Self.isRetained(snapshot.provenance, at: now()) else {
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
                    shouldKeep = Self.isRetained(
                        try decodedSnapshot(at: entry).provenance,
                        at: referenceDate
                    )
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
///
/// This provider intentionally serves snapshots the origin provider already
/// considers expired. That is the whole point of an offline fallback: NWS
/// snapshots expire in 30 minutes and WeatherKit's in an hour, so gating on the
/// origin expiry would make `maxAge` unreachable and leave an angler out of
/// signal with nothing. The delivery is re-stamped as `.cache` with
/// `isFallback: true` and its own short validity window, so the UI shows it as
/// cached and the app keeps retrying the live providers.
struct CachedWeatherProvider: WeatherProvider {
    typealias Clock = @Sendable () -> Date

    static let defaultMaxAge: TimeInterval = 24 * 3_600

    /// How long one cache *delivery* stays presentable before the app must ask
    /// the live providers again. Independent of how old the data itself is.
    static let deliveryLifetime: TimeInterval = 15 * 60

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
              persisted.provenance.fetchedAt.timeIntervalSinceReferenceDate.isFinite
        else {
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
            pressureHistory: persisted.pressureHistory,
            provenance: WeatherProvenance(
                source: .cache,
                fetchedAt: persisted.provenance.fetchedAt,
                isFallback: true,
                attribution: "Cached from \(origin)",
                providerAttribution: persisted.provenance.providerAttribution,
                // The delivery gets its own window. `fetchedAt` stays original
                // so every surface remains honest about how old the data is.
                expiresAt: referenceDate.addingTimeInterval(Self.deliveryLifetime)
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
