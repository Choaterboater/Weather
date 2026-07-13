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
        #expect(header.version == 1)
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
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let newer = makeSnapshot(
            source: .nws,
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_300)
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
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let existing = makeSnapshot(source: .nws, fetchedAt: fetchedAt)
        let equalIncoming = makeSnapshot(source: .weatherKit, fetchedAt: fetchedAt)

        try await cache.save(existing)
        try await cache.save(equalIncoming)

        let loaded = await cache.load(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049)
        )
        #expect(loaded == existing)
    }

    @Test func missingSnapshotReturnsNil() async {
        let cache = WeatherSnapshots(directory: tempDirectory())

        let loaded = await cache.load(
            for: CLLocation(latitude: 10, longitude: 10)
        )

        #expect(loaded == nil)
    }

    @Test func corruptEnvelopeIsBackedUpBeforeReturningNil() async throws {
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
        let backups = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("303,-860.invalid-") }
        #expect(backups.count == 1)
        let backup = try #require(backups.first)
        #expect(try Data(contentsOf: backup) == Data("not-json".utf8))
    }

    @Test func unknownEnvelopeVersionIsBackedUpBeforeReturningNil() async throws {
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
        let backups = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("303,-860.invalid-") }
        #expect(backups.count == 1)
        let backup = try #require(backups.first)
        #expect(try Data(contentsOf: backup) == unknown)
    }

    @Test func savingOverCorruptFileBacksItUpBeforeWritingSnapshot() async throws {
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
        let backups = try invalidBackups(in: directory)
        #expect(loaded == snapshot)
        #expect(backups.count == 1)
        let backup = try #require(backups.first)
        #expect(try Data(contentsOf: backup) == corrupt)
    }

    @Test func savingOverUnknownVersionBacksItUpBeforeWritingSnapshot() async throws {
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
        let backups = try invalidBackups(in: directory)
        #expect(loaded == snapshot)
        #expect(backups.count == 1)
        let backup = try #require(backups.first)
        #expect(try Data(contentsOf: backup) == unknown)
    }

    @Test func backupFailureThrowsWithoutOverwritingPriorBytes() async throws {
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
            fileManager: MoveFailingFileManager()
        )

        await #expect(throws: MoveFailingFileManager.Failure.self) {
            try await cache.save(makeSnapshot(source: .nws))
        }

        #expect(try Data(contentsOf: file) == corrupt)
        #expect(try invalidBackups(in: directory).isEmpty)
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
            attribution: "Cached from National Weather Service"
        ))
    }

    @Test("Cached provider rejects a forecast older than its maximum age")
    func cachedProviderRejectsExpiredSnapshot() async throws {
        let cache = WeatherSnapshots(directory: tempDirectory())
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
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
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
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

    private func invalidBackups(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("303,-860.invalid-") }
    }

    private func makeSnapshot(
        source: WeatherSource,
        fetchedAt date: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> WeatherSnapshot {
        let wind = WindSnapshot(
            directionDegrees: 225,
            speedMetersPerSecond: 4.5,
            gustMetersPerSecond: 7
        )
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
                attribution: source == .nws ? "National Weather Service" : nil
            )
        )
    }
}

private final class MoveFailingFileManager: FileManager, @unchecked Sendable {
    enum Failure: Error {
        case refused
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        throw Failure.refused
    }
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
