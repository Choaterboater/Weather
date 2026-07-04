import CoreLocation
import Foundation
import Testing
@testable import BiteCast

@MainActor
@Suite("WeatherSnapshots", .serialized)
struct WeatherSnapshotsTests {
    /// Points the store at a fresh temp directory and returns it.
    private func useTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeatherSnapshotsTests-\(UUID().uuidString)", isDirectory: true)
        WeatherSnapshots.baseDirectory = dir
        return dir
    }

    private func makeSamples(count: Int, start: Date) -> [HourSample] {
        (0..<count).map { i in
            HourSample(
                date: start.addingTimeInterval(Double(i) * 3600),
                temperature: 70 + Double(i),
                pressureHPa: 1015 - Double(i) * 0.5,
                precipChance: 0.1 * Double(i % 5)
            )
        }
    }

    @Test
    func roundTripSavesAndReadsBack() {
        _ = useTempDirectory()
        let location = CLLocation(latitude: 30.2, longitude: -87.5)
        let stamp = Date(timeIntervalSince1970: 1_750_000_000)
        let samples = makeSamples(count: 6, start: stamp)
        let reading = PressureReading(
            pressure: Measurement(value: 1013.2, unit: UnitPressure.hectopascals),
            tendency: .falling,
            changePerHour: -0.8
        )

        WeatherSnapshots.save(samples: samples, pressure: reading, for: location, timestamp: stamp)

        let cachedSamples = WeatherSnapshots.cachedSamples(for: location)
        #expect(cachedSamples.count == 6)
        #expect(cachedSamples.first?.temperature == 70)
        #expect(cachedSamples.last?.pressureHPa == 1012.5)

        let cachedPressure = WeatherSnapshots.cachedPressure(for: location)
        #expect(cachedPressure?.tendency == .falling)
        #expect(cachedPressure?.changePerHour == -0.8)
        #expect(cachedPressure?.pressure.converted(to: .hectopascals).value == 1013.2)

        // ISO-8601 encoding keeps second precision.
        let cachedStamp = WeatherSnapshots.cachedTimestamp(for: location)
        #expect(cachedStamp.map { abs($0.timeIntervalSince(stamp)) < 1 } == true)
    }

    @Test(arguments: [PressureTendency.rising, .falling, .steady])
    func tendencyStringSurvivesRoundTrip(tendency: PressureTendency) {
        _ = useTempDirectory()
        let location = CLLocation(latitude: 44.9, longitude: -93.2)
        let reading = PressureReading(
            pressure: Measurement(value: 1010, unit: UnitPressure.hectopascals),
            tendency: tendency,
            changePerHour: nil
        )
        WeatherSnapshots.save(samples: [], pressure: reading, for: location)
        #expect(WeatherSnapshots.cachedPressure(for: location)?.tendency == tendency)
    }

    @Test
    func missingSnapshotReturnsEmpty() {
        _ = useTempDirectory()
        let location = CLLocation(latitude: 10, longitude: 10)
        #expect(WeatherSnapshots.cachedSamples(for: location).isEmpty)
        #expect(WeatherSnapshots.cachedPressure(for: location) == nil)
        #expect(WeatherSnapshots.cachedTimestamp(for: location) == nil)
    }

    @Test
    func nearbyCoordinatesShareATile() {
        _ = useTempDirectory()
        let saved = CLLocation(latitude: 30.2, longitude: -87.5)
        let nearby = CLLocation(latitude: 30.24, longitude: -87.54)   // same 0.1° tile
        let reading = PressureReading(
            pressure: Measurement(value: 1020, unit: UnitPressure.hectopascals),
            tendency: .rising,
            changePerHour: 0.5
        )
        WeatherSnapshots.save(samples: [], pressure: reading, for: saved)
        #expect(WeatherSnapshots.cachedPressure(for: nearby)?.tendency == .rising)
    }

    @Test
    func geoTileKeysAreStableIntegerIndices() {
        // Integer tile indices — no float-interpolation artifacts like "30.200000000000003".
        #expect(GeoTile.key(lat: 30.2, lon: -87.5) == "302,-875")
        #expect(GeoTile.key(lat: 30.24, lon: -87.54) == "302,-875")
        #expect(GeoTile.key(lat: 0, lon: 0) == "0,0")
        #expect(GeoTile.key(lat: -33.86, lon: 151.21) == "-339,1512")
        #expect(!GeoTile.key(lat: 30.2, lon: -87.5).contains("."))
    }
}
