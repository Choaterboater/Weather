import Foundation
import Testing
import WeatherKit
@testable import BiteCast

/// Sanity checks for the FishingScorer. Targets the score bands defined in
/// FishingScore.summary so the tests stay stable as we tweak factor weights:
///
///   * 85+ Excellent · 70–84 Strong · 50–69 Fair · 30–49 Tough · <30 Poor
@Suite("FishingScorer")
struct FishingScorerTests {

    // MARK: - Headline scenarios from the plan

    /// Falling pressure + active major window + new moon should hit the
    /// "Excellent" band (85+).
    @Test
    func excellentDayHitsTopBand() {
        let now = Self.fixedSpringDate
        let major = BiteWindow(period: .major, peak: now, cause: "Moon overhead")

        let score = FishingScorer.score(
            moonPhase: .new,
            activeWindow: major,
            nextWindow: nil,
            pressureTendency: .falling,
            pressureChangePerHour: -1.2,
            windMph: 8,
            species: .bass,
            tideEvents: [],
            now: now
        )

        #expect(score.overall >= 85, "Excellent-day score was \(score.overall)")
        #expect(score.summary == "Excellent")
    }

    /// Heavy wind + steady pressure + waxing crescent + no nearby window
    /// should fall into the "Tough" / "Fair" range — somewhere 30–55.
    @Test
    func toughDayLandsInLowBand() {
        let now = Self.fixedSpringDate
        let farOff = BiteWindow(period: .minor, peak: now.addingTimeInterval(6 * 3600), cause: "Moonrise")

        let score = FishingScorer.score(
            moonPhase: .waxingCrescent,
            activeWindow: nil,
            nextWindow: farOff,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 28,
            species: .bass,
            tideEvents: [],
            now: now
        )

        #expect(score.overall >= 30 && score.overall <= 60,
                "Tough-day score was \(score.overall)")
    }

    // MARK: - Per-factor behavior

    @Test
    func freshwaterRedistributesTideWeight() {
        let now = Self.fixedSpringDate

        let salt = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .redfish,
            tideEvents: [TideEvent(time: now, kind: .high, heightFeet: 2.0)],
            now: now
        )
        let fresh = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .bass,
            tideEvents: [],
            now: now
        )

        let saltLabels = Set(salt.factors.map(\.label))
        let freshLabels = Set(fresh.factors.map(\.label))
        #expect(saltLabels.contains("Tide"))
        #expect(!freshLabels.contains("Tide"))

        // Weights should still sum to ~1.0 in both cases.
        let saltWeight = salt.factors.map(\.weight).reduce(0, +)
        let freshWeight = fresh.factors.map(\.weight).reduce(0, +)
        #expect(abs(saltWeight - 1.0) < 0.001)
        #expect(abs(freshWeight - 1.0) < 0.001)
    }

    @Test
    func fallingPressureBeatsRising() {
        let now = Self.fixedSpringDate
        let fall = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .falling,
            pressureChangePerHour: -1.0,
            windMph: 8,
            species: .bass,
            now: now
        )
        let rise = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .rising,
            pressureChangePerHour: 1.0,
            windMph: 8,
            species: .bass,
            now: now
        )
        #expect(fall.overall > rise.overall,
                "falling=\(fall.overall) rising=\(rise.overall)")
    }

    @Test
    func tideMidphaseBeatsSlackWater() {
        let now = Self.fixedSpringDate
        let slackEvent = TideEvent(time: now, kind: .high, heightFeet: 2.0)
        let movingEvent = TideEvent(time: now.addingTimeInterval(90 * 60), kind: .high, heightFeet: 2.0)

        let slack = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .redfish,
            tideEvents: [slackEvent],
            now: now
        )
        let moving = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .redfish,
            tideEvents: [movingEvent],
            now: now
        )
        #expect(moving.overall > slack.overall,
                "moving=\(moving.overall) slack=\(slack.overall)")
    }

    @Test
    func overallStaysInZeroToHundred() {
        let now = Self.fixedSpringDate
        let absurdLow = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .rising,
            pressureChangePerHour: 0,
            windMph: 60,
            species: .bass,
            tideEvents: [],
            now: now
        )
        let absurdHigh = FishingScorer.score(
            moonPhase: .new,
            activeWindow: BiteWindow(period: .major, peak: now, cause: "Moon overhead"),
            nextWindow: nil,
            pressureTendency: .falling,
            pressureChangePerHour: -3.0,
            windMph: 8,
            species: .bass,
            tideEvents: [],
            now: now
        )
        #expect(absurdLow.overall >= 0)
        #expect(absurdLow.overall <= 100)
        #expect(absurdHigh.overall >= 0)
        #expect(absurdHigh.overall <= 100)
    }

    // MARK: - Helpers

    /// 2026-05-15 12:00 local — bass is in peak season, isolated month.
    private static var fixedSpringDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 15
        components.hour = 12
        return Calendar.current.date(from: components)!
    }
}
