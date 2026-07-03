import Foundation
import Testing
@testable import BiteCast

/// The trend math behind the Pressure card and the scorer's pressure factor.
/// Regression armor for the near-zero-baseline bug: a sample only minutes old
/// must never be treated as a trend baseline.
@Suite("PressureReading")
struct PressureReadingTests {
    private static let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func sample(hoursAgo: Double, hPa: Double) -> (date: Date, hPa: Double) {
        (date: Self.now.addingTimeInterval(-hoursAgo * 3600), hPa: hPa)
    }

    @Test
    func fallingPressureOverThreeHoursReadsFalling() {
        let reading = PressureReading.analyze(
            nowHPa: 1010,
            history: [sample(hoursAgo: 3, hPa: 1013)],
            now: Self.now,
            fallback: .steady
        )
        #expect(reading.tendency == .falling)
        let perHour = try! #require(reading.changePerHour)
        #expect(abs(perHour - (-1.0)) < 0.001)
    }

    @Test
    func risingPressureOverThreeHoursReadsRising() {
        let reading = PressureReading.analyze(
            nowHPa: 1016,
            history: [sample(hoursAgo: 3, hPa: 1013)],
            now: Self.now,
            fallback: .steady
        )
        #expect(reading.tendency == .rising)
    }

    @Test
    func smallDriftReadsSteady() {
        // 0.2 hPa over 3 h = 0.067 hPa/hr, well inside the ±0.3 threshold.
        let reading = PressureReading.analyze(
            nowHPa: 1013.2,
            history: [sample(hoursAgo: 3, hPa: 1013.0)],
            now: Self.now,
            fallback: .falling
        )
        #expect(reading.tendency == .steady)
    }

    @Test
    func baselineYoungerThanOneHourFallsBackInsteadOfAmplifyingNoise() {
        // A 0.2 hPa forecast-vs-observation mismatch 3 minutes past the hour
        // used to read as 4 hPa/hr and spuriously flip the tendency.
        let reading = PressureReading.analyze(
            nowHPa: 1010.2,
            history: [sample(hoursAgo: 0.05, hPa: 1010.0)],
            now: Self.now,
            fallback: .steady
        )
        #expect(reading.tendency == .steady)
        #expect(reading.changePerHour == nil)
    }

    @Test
    func emptyHistoryUsesFallbackTendency() {
        let reading = PressureReading.analyze(
            nowHPa: 1010,
            history: [],
            now: Self.now,
            fallback: .rising
        )
        #expect(reading.tendency == .rising)
        #expect(reading.changePerHour == nil)
    }

    @Test
    func sampleNearestToThreeHoursAgoDrivesTheSlope() {
        let reading = PressureReading.analyze(
            nowHPa: 1010,
            history: [sample(hoursAgo: 6, hPa: 1020), sample(hoursAgo: 3, hPa: 1013)],
            now: Self.now,
            fallback: .steady
        )
        let perHour = try! #require(reading.changePerHour)
        #expect(abs(perHour - (-1.0)) < 0.001)
    }

    @Test
    func futureSamplesAreIgnored() {
        let reading = PressureReading.analyze(
            nowHPa: 1010,
            history: [sample(hoursAgo: -2, hPa: 1000), sample(hoursAgo: 3, hPa: 1013)],
            now: Self.now,
            fallback: .steady
        )
        let perHour = try! #require(reading.changePerHour)
        #expect(abs(perHour - (-1.0)) < 0.001)
    }
}
