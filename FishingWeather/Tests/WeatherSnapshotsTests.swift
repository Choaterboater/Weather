import CoreLocation
import Foundation
import Testing
@testable import BiteCast

@Suite("WeatherSnapshots", .serialized)
struct WeatherSnapshotsTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WeatherSnapshotsTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func versionedSnapshotRoundTripPreservesExactProvenance() async throws {
        let directory = tempDirectory()
        let cache = WeatherSnapshots(directory: directory)
        let snapshot = makeSnapshot(source: .nws)

        try await cache.save(snapshot)
        let loaded = await cache.load(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )

        #expect(loaded == snapshot)
        #expect(loaded?.provenance == snapshot.provenance)

        let file = directory.appendingPathComponent("303,-860.json")
        let header = try JSONDecoder().decode(
            EnvelopeHeader.self,
            from: Data(contentsOf: file)
        )
        #expect(header.version == 2)
    }

    @Test func nearbyCoordinatesLoadTheMatchingGeoTile() async throws {
        let cache = WeatherSnapshots(directory: tempDirectory())
        let snapshot = makeSnapshot(source: .weatherKit)
        try await cache.save(snapshot)

        let loaded = await cache.load(
            for: CLLocation(latitude: 30.31, longitude: -86.01)
        )

        #expect(loaded == snapshot)
    }

    @Test func delayedOlderSaveCannotOverwriteNewerSnapshot() async throws {
        let cache = WeatherSnapshots(directory: tempDirectory())
        let gate = CacheSaveGate()
        let older = makeSnapshot(
            source: .weatherKit,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newer = makeSnapshot(
            source: .nws,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_300)
        )

        let delayedOlderSave = Task {
            await gate.markStarted()
            await gate.waitForRelease()
            try await cache.save(older)
        }
        await gate.waitUntilStarted()
        try await cache.save(newer)
        await gate.release()
        try await delayedOlderSave.value

        let loaded = await cache.load(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )
        #expect(loaded == newer)
    }

    @Test func equalFetchTimeKeepsExistingSnapshotDeterministically() async throws {
        let cache = WeatherSnapshots(directory: tempDirectory())
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = makeSnapshot(source: .nws, fetchedAt: fetchedAt)
        let equalIncoming = makeSnapshot(source: .weatherKit, fetchedAt: fetchedAt)

        try await cache.save(existing)
        try await cache.save(equalIncoming)

        let loaded = await cache.load(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )
        #expect(loaded == existing)
    }

    @Test("A future existing snapshot is purged after clock correction")
    func futureExistingSnapshotIsReplaceableAfterClockCorrection() async throws {
        let directory = tempDirectory()
        let correctedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let future = makeSnapshot(
            source: .nws,
            fetchedAt: correctedNow.addingTimeInterval(3_600)
        )
        let corrected = makeSnapshot(
            source: .weatherKit,
            fetchedAt: correctedNow
        )
        try writeEnvelope(future, to: directory)
        let cache = WeatherSnapshots(
            directory: directory,
            now: { correctedNow }
        )

        try await cache.save(corrected)

        let loaded = await cache.load(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )
        #expect(loaded == corrected)
        #expect(try invalidBackups(in: directory).isEmpty)
    }

    @Test("A valid newer existing snapshot still wins over an older save")
    func validNewerExistingSnapshotStillWins() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = WeatherSnapshots(
            directory: tempDirectory(),
            now: { now }
        )
        let newer = makeSnapshot(
            source: .nws,
            fetchedAt: now.addingTimeInterval(-60)
        )
        let older = makeSnapshot(
            source: .weatherKit,
            fetchedAt: now.addingTimeInterval(-300)
        )

        try await cache.save(newer)
        try await cache.save(older)

        let loaded = await cache.load(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )
        #expect(loaded == newer)
    }

    @Test("An incoming future snapshot is rejected without touching the cache")
    func incomingFutureSnapshotIsRejected() async throws {
        let directory = tempDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = WeatherSnapshots(
            directory: directory,
            now: { now }
        )
        let existing = makeSnapshot(
            source: .weatherKit,
            fetchedAt: now.addingTimeInterval(-60)
        )
        let future = makeSnapshot(
            source: .nws,
            fetchedAt: now.addingTimeInterval(3_600)
        )
        var didThrow = false

        try await cache.save(existing)
        do {
            try await cache.save(future)
        } catch {
            didThrow = true
        }

        let loaded = await cache.load(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )
        #expect(didThrow)
        #expect(loaded == existing)
        #expect(try invalidBackups(in: directory).isEmpty)
    }

    @Test func missingSnapshotReturnsNil() async {
        let cache = WeatherSnapshots(directory: tempDirectory())

        let loaded = await cache.load(
            for: CLLocation(latitude: 10, longitude: 10)
        )

        #expect(loaded == nil)
    }

    @Test func corruptEnvelopeIsDeletedBeforeReturningNil() async throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent("303,-860.json")
        try Data("not-json".utf8).write(to: file)
        let cache = WeatherSnapshots(directory: directory)

        let loaded = await cache.load(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )

        #expect(loaded == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    @Test func unknownEnvelopeVersionIsDeletedBeforeReturningNil() async throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent("303,-860.json")
        let unknown = Data(#"{"version":999,"snapshot":{}}"#.utf8)
        try unknown.write(to: file)
        let cache = WeatherSnapshots(directory: directory)

        let loaded = await cache.load(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )

        #expect(loaded == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    @Test("Cache sweep removes every unexpected non-hidden child")
    func unexpectedCacheEntriesArePurged() async throws {
        let directory = tempDirectory()
        let cache = WeatherSnapshots(directory: directory)
        let snapshot = makeSnapshot(source: .nws)
        try await cache.save(snapshot)

        let strayFile = directory.appendingPathComponent("notes.tmp")
        let strayDirectory = directory.appendingPathComponent(
            "old-provider",
            isDirectory: true
        )
        try Data("unexpected".utf8).write(to: strayFile)
        try FileManager.default.createDirectory(
            at: strayDirectory,
            withIntermediateDirectories: true
        )
        try Data("nested".utf8).write(
            to: strayDirectory.appendingPathComponent("snapshot.bin")
        )

        let loaded = await cache.load(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )

        #expect(loaded == snapshot)
        #expect(!FileManager.default.fileExists(atPath: strayFile.path))
        #expect(!FileManager.default.fileExists(atPath: strayDirectory.path))
        let remaining = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(remaining.map(\.lastPathComponent) == ["303,-860.json"])
    }

    @Test func savingOverCorruptFileDeletesItBeforeWritingSnapshot() async throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent("303,-860.json")
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: file)
        let cache = WeatherSnapshots(directory: directory)
        let snapshot = makeSnapshot(source: .nws)

        try await cache.save(snapshot)

        let loaded = await cache.load(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )
        #expect(loaded == snapshot)
        #expect(try invalidBackups(in: directory).isEmpty)
    }

    @Test func savingOverUnknownVersionDeletesItBeforeWritingSnapshot() async throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent("303,-860.json")
        let unknown = Data(#"{"version":999,"snapshot":{}}"#.utf8)
        try unknown.write(to: file)
        let cache = WeatherSnapshots(directory: directory)
        let snapshot = makeSnapshot(source: .weatherKit)

        try await cache.save(snapshot)

        let loaded = await cache.load(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )
        #expect(loaded == snapshot)
        #expect(try invalidBackups(in: directory).isEmpty)
    }

    @Test func purgeFailureThrowsWithoutOverwritingPriorBytes() async throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent("303,-860.json")
        let corrupt = Data("irreplaceable-invalid-bytes".utf8)
        try corrupt.write(to: file)
        let cache = WeatherSnapshots(
            directory: directory,
            fileManager: RemoveFailingFileManager()
        )

        await #expect(throws: RemoveFailingFileManager.Failure.self) {
            try await cache.save(makeSnapshot(source: .nws))
        }

        #expect(try Data(contentsOf: file) == corrupt)
        #expect(try invalidBackups(in: directory).isEmpty)
    }

    @Test("Expired disk snapshots are deleted and never returned")
    func expiredDiskSnapshotIsRejectedAndPurged() async throws {
        let directory = tempDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = makeSnapshot(
            source: .weatherKit,
            fetchedAt: now.addingTimeInterval(-3_600),
            expiresAt: now.addingTimeInterval(-1),
            providerAttribution: .appleFixture
        )
        try writeEnvelope(snapshot, to: directory)
        let cache = WeatherSnapshots(directory: directory, now: { now })

        let loaded = await cache.load(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )

        #expect(loaded == nil)
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("303,-860.json").path
        ))
        #expect(try invalidBackups(in: directory).isEmpty)
    }

    @Test("Legacy Application Support weather cache is removed without recovery files")
    func legacyDirectoryIsPurged() async throws {
        let directory = tempDirectory().appendingPathComponent("new", isDirectory: true)
        let legacy = tempDirectory().appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("legacy-weather".utf8).write(
            to: legacy.appendingPathComponent("303,-860.json")
        )

        let cache = WeatherSnapshots(directory: directory, legacyDirectory: legacy)
        _ = await cache.load(for: CLLocation(latitude: 30.2938, longitude: -86.0049))

        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(!FileManager.default.fileExists(
            atPath: legacy.deletingLastPathComponent()
                .appendingPathComponent("legacy.invalid.json").path
        ))
    }

    @Test("Default weather cache uses Caches and is excluded from device backup")
    func defaultPathAndBackupExclusion() async throws {
        let defaultDirectory = WeatherSnapshots.defaultDirectory()
        #expect(defaultDirectory.path.contains("/Library/Caches/"))
        #expect(defaultDirectory.path.hasSuffix("/BiteCast/WeatherSnapshots"))

        let directory = tempDirectory()
        let cache = WeatherSnapshots(directory: directory)
        try await cache.save(makeSnapshot(source: .nws))

        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("Cached Apple data retains required marks only until provider expiry")
    func cachedAppleAttributionRetainedBeforeExpiry() async throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let expiresAt = fetchedAt.addingTimeInterval(30 * 60)
        let cache = WeatherSnapshots(
            directory: tempDirectory(),
            now: { fetchedAt }
        )
        let original = makeSnapshot(
            source: .weatherKit,
            fetchedAt: fetchedAt,
            expiresAt: expiresAt,
            providerAttribution: .appleFixture
        )
        try await cache.save(original)

        let cached = try await CachedWeatherProvider(
            cache: cache,
            now: { expiresAt.addingTimeInterval(-1) }
        ).forecast(for: CLLocation(latitude: 30.2938, longitude: -86.0049))

        #expect(cached.provenance.source == .cache)
        #expect(cached.provenance.providerAttribution == .appleFixture)
        #expect(cached.provenance.expiresAt == expiresAt)
    }

    @Test("Cached Apple data without usable combined marks fails closed")
    func cachedAppleWithoutMarksIsRejected() async throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let directory = tempDirectory()
        let cache = WeatherSnapshots(directory: directory, now: { fetchedAt })
        let original = makeSnapshot(
            source: .weatherKit,
            fetchedAt: fetchedAt,
            expiresAt: fetchedAt.addingTimeInterval(30 * 60),
            providerAttribution: .appleWithoutMarks,
            overridesDefaultAttribution: true
        )
        try writeEnvelope(original, to: directory)

        await #expect(throws: WeatherProviderError.serviceUnavailable) {
            _ = try await CachedWeatherProvider(
                cache: cache,
                now: { fetchedAt.addingTimeInterval(60) }
            ).forecast(for: CLLocation(latitude: 30.2938, longitude: -86.0049))
        }
    }

    @Test("Cached WeatherKit data rejects missing or mismatched provider identity")
    func cachedWeatherKitProviderIdentityMustMatch() async throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let location = CLLocation(latitude: 30.2938, longitude: -86.0049)

        for attribution in [nil, WeatherProviderAttribution.nationalWeatherService] {
            let directory = tempDirectory()
            let cache = WeatherSnapshots(directory: directory, now: { fetchedAt })
            try writeEnvelope(makeSnapshot(
                source: .weatherKit,
                fetchedAt: fetchedAt,
                expiresAt: fetchedAt.addingTimeInterval(30 * 60),
                providerAttribution: attribution,
                overridesDefaultAttribution: true
            ), to: directory)

            await #expect(throws: WeatherProviderError.serviceUnavailable) {
                _ = try await CachedWeatherProvider(
                    cache: cache,
                    now: { fetchedAt.addingTimeInterval(60) }
                ).forecast(for: location)
            }
        }
    }

    @Test func cachedProviderMarksOriginalSnapshotAsCachedFallback() async throws {
        let cache = WeatherSnapshots(directory: tempDirectory())
        let original = makeSnapshot(source: .nws)
        try await cache.save(original)

        let cached = try await CachedWeatherProvider(
            cache: cache,
            now: { original.provenance.fetchedAt.addingTimeInterval(60) }
        ).forecast(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )

        #expect(cached.coordinate == original.coordinate)
        #expect(cached.current == original.current)
        #expect(cached.hourly == original.hourly)
        #expect(cached.daily == original.daily)
        #expect(cached.alerts == original.alerts)
        #expect(cached.astronomy == original.astronomy)
        #expect(cached.provenance == WeatherProvenance(
            source: .cache,
            fetchedAt: original.provenance.fetchedAt,
            isFallback: true,
            attribution: "Cached from National Weather Service",
            providerAttribution: original.provenance.providerAttribution,
            expiresAt: original.provenance.expiresAt
        ))
    }

    @Test("Cached provider rejects a forecast older than its maximum age")
    func cachedProviderRejectsExpiredSnapshot() async throws {
        let cache = WeatherSnapshots(directory: tempDirectory())
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await cache.save(makeSnapshot(source: .nws, fetchedAt: fetchedAt))
        let provider = CachedWeatherProvider(
            cache: cache,
            maxAge: 24 * 3_600,
            now: { fetchedAt.addingTimeInterval(24 * 3_600 + 1) }
        )

        await #expect(throws: WeatherProviderError.serviceUnavailable) {
            _ = try await provider.forecast(
                for: CLLocation(latitude: 30.2938, longitude: -86.0049)
            )
        }
    }

    @Test("Cached provider rejects a forecast timestamp from the future")
    func cachedProviderRejectsFutureSnapshot() async throws {
        let cache = WeatherSnapshots(directory: tempDirectory())
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await cache.save(makeSnapshot(source: .nws, fetchedAt: fetchedAt))
        let provider = CachedWeatherProvider(
            cache: cache,
            maxAge: 24 * 3_600,
            now: { fetchedAt.addingTimeInterval(-1) }
        )

        await #expect(throws: WeatherProviderError.serviceUnavailable) {
            _ = try await provider.forecast(
                for: CLLocation(latitude: 30.2938, longitude: -86.0049)
            )
        }
    }

    @Test func cachedProviderReportsServiceUnavailableWhenTileIsMissing() async {
        let provider = CachedWeatherProvider(
            cache: WeatherSnapshots(directory: tempDirectory())
        )

        await #expect(throws: WeatherProviderError.serviceUnavailable) {
            _ = try await provider.forecast(
                for: CLLocation(latitude: 30.2938, longitude: -86.0049)
            )
        }
    }

    @Test func geoTileKeysAreStableIntegerIndices() {
        #expect(GeoTile.key(lat: 30.2, lon: -87.5) == "302,-875")
        #expect(GeoTile.key(lat: 30.24, lon: -87.54) == "302,-875")
        #expect(GeoTile.key(lat: 0, lon: 0) == "0,0")
        #expect(GeoTile.key(lat: -33.86, lon: 151.21) == "-339,1512")
        #expect(!GeoTile.key(lat: 30.2, lon: -87.5).contains("."))
    }

    private struct EnvelopeHeader: Decodable {
        let version: Int
    }

    private struct SnapshotEnvelope: Codable {
        let version: Int
        let snapshot: WeatherSnapshot
    }

    private func invalidBackups(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("303,-860.invalid-") }
    }

    private func writeEnvelope(
        _ snapshot: WeatherSnapshot,
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent("303,-860.json")
        let envelope = SnapshotEnvelope(version: 2, snapshot: snapshot)
        try JSONEncoder().encode(envelope).write(to: file, options: .atomic)
    }

    private func makeSnapshot(
        source: WeatherSource,
        fetchedAt date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        expiresAt: Date = .distantFuture,
        providerAttribution: WeatherProviderAttribution? = nil,
        overridesDefaultAttribution: Bool = false
    ) -> WeatherSnapshot {
        let wind = WindSnapshot(
            directionDegrees: 225,
            speedMetersPerSecond: 4.5,
            gustMetersPerSecond: 7
        )
        let resolvedAttribution: WeatherProviderAttribution? = if overridesDefaultAttribution {
            providerAttribution
        } else if let providerAttribution {
            providerAttribution
        } else {
            switch source {
            case .weatherKit: .appleFixture
            case .nws: .nationalWeatherService
            case .cache: nil
            }
        }
        return WeatherSnapshot(
            coordinate: WeatherCoordinate(latitude: 30.2938, longitude: -86.0049),
            timeZoneIdentifier: "America/Chicago",
            current: CurrentConditionsSnapshot(
                date: date,
                temperatureCelsius: 25.4,
                apparentTemperatureCelsius: 26.1,
                dewPointCelsius: 20.2,
                humidityFraction: 0.72,
                pressureHPa: 1_019,
                visibilityMeters: 16_000,
                uvIndex: 5,
                conditionText: "Partly Cloudy",
                symbolName: "cloud.sun",
                wind: wind
            ),
            hourly: [HourlyWeatherPoint(
                date: date,
                temperatureCelsius: 25.4,
                apparentTemperatureCelsius: 26.1,
                dewPointCelsius: 20.2,
                humidityFraction: 0.72,
                pressureHPa: 1_019,
                visibilityMeters: 16_000,
                uvIndex: 5,
                cloudCoverFraction: 0.35,
                precipitationChance: 0.15,
                precipitationMM: 0,
                conditionText: "Partly Cloudy",
                symbolName: "cloud.sun",
                wind: wind
            )],
            daily: [DailyWeatherPoint(
                date: date,
                lowCelsius: 22.2,
                highCelsius: 29.4,
                precipitationChance: 0.2,
                conditionText: "Partly Cloudy",
                symbolName: "cloud.sun",
                windMetersPerSecond: 5,
                windPeakMetersPerSecond: 8,
                astronomy: AstronomySnapshot(
                    sunrise: date.addingTimeInterval(-6 * 3_600),
                    sunset: date.addingTimeInterval(6 * 3_600),
                    moonrise: date.addingTimeInterval(-3 * 3_600),
                    moonset: date.addingTimeInterval(9 * 3_600),
                    moonTransit: date.addingTimeInterval(3 * 3_600),
                    moonPhaseFraction: 0.25
                )
            )],
            alerts: [],
            astronomy: AstronomySnapshot(
                sunrise: date.addingTimeInterval(-6 * 3_600),
                sunset: date.addingTimeInterval(6 * 3_600),
                moonrise: date.addingTimeInterval(-3 * 3_600),
                moonset: date.addingTimeInterval(9 * 3_600),
                moonTransit: date.addingTimeInterval(3 * 3_600),
                moonPhaseFraction: 0.25
            ),
            provenance: WeatherProvenance(
                source: source,
                fetchedAt: date,
                isFallback: false,
                attribution: source == .nws ? "National Weather Service" : nil,
                providerAttribution: resolvedAttribution,
                expiresAt: expiresAt
            )
        )
    }
}

private final class RemoveFailingFileManager: FileManager, @unchecked Sendable {
    enum Failure: Error {
        case refused
    }

    override func removeItem(at URL: URL) throws {
        throw Failure.refused
    }
}

private extension WeatherProviderAttribution {
    static let markData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL9WQAAAABJRU5ErkJggg=="
    )!

    static let appleFixture = Self(
        providerKind: .appleWeather,
        serviceName: "Apple Weather",
        legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
        combinedMarkLightURL: URL(string: "https://weatherkit.apple.com/assets/light.png")!,
        combinedMarkDarkURL: URL(string: "https://weatherkit.apple.com/assets/dark.png")!,
        legalText: "Weather data sources and legal attribution",
        combinedMarkLightData: markData,
        combinedMarkDarkData: markData
    )

    static let appleWithoutMarks = Self(
        providerKind: .appleWeather,
        serviceName: "Apple Weather",
        legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
        combinedMarkLightURL: URL(string: "https://weatherkit.apple.com/assets/light.png")!,
        combinedMarkDarkURL: URL(string: "https://weatherkit.apple.com/assets/dark.png")!,
        legalText: "Weather data sources and legal attribution"
    )
}

private actor CacheSaveGate {
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitForRelease() async {
        if released { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
