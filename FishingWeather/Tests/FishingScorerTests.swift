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

    @Test
    func solunarProximityFallsOffWithTime() {
        let now = Date()
        let major = BiteWindow(period: .major, peak: now, cause: "Moon overhead")
        let near = Date().addingTimeInterval(30 * 60) // +30 min
        let far = Date().addingTimeInterval(3 * 3600) // +3 hr

        let atPeak = FishingScorer.score(
            moonPhase: .full,
            activeWindow: major,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .bass,
            now: now
        ).factors.first { $0.kind == .solunar }!.raw

        let nearScore = FishingScorer.score(
            moonPhase: .full,
            activeWindow: nil,
            nextWindow: BiteWindow(period: .major, peak: near, cause: "Moon overhead"),
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .bass,
            now: now
        ).factors.first { $0.kind == .solunar }!.raw

        let farScore = FishingScorer.score(
            moonPhase: .full,
            activeWindow: nil,
            nextWindow: BiteWindow(period: .major, peak: far, cause: "Moon overhead"),
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .bass,
            now: now
        ).factors.first { $0.kind == .solunar }!.raw

        #expect(atPeak > nearScore)
        #expect(nearScore > farScore)
    }

    @Test
    func windInterpolationIsSmoothAcrossThresholds() {
        // Compare just under/over the 6 mph ideal threshold.
        let fivePointNine = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 5.9,
            species: .bass
        ).factors.first { $0.kind == .wind }!.raw

        let sixPointOne = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 6.1,
            species: .bass
        ).factors.first { $0.kind == .wind }!.raw

        // Should be close, not a cliff.
        #expect(abs(sixPointOne - fivePointNine) < 0.1)
    }

    @Test
    func tideRangeAddsSmallBoostWhenAvailable() {
        let now = Date()
        // Simulate a day with a 4 ft swing.
        let events = [
            TideEvent(time: now.addingTimeInterval(-3 * 3600), kind: .low, heightFeet: 0.5),
            TideEvent(time: now.addingTimeInterval(-30 * 60), kind: .high, heightFeet: 4.5)
        ]
        let base = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .redfish,
            tideEvents: events,
            now: now
        ).factors.first { $0.kind == .tide }!.raw

        // Compare to flat-range variant (no boost expected)
        let flatHeightEvents = [
            TideEvent(time: now.addingTimeInterval(-3 * 3600), kind: .low, heightFeet: 2.5),
            TideEvent(time: now.addingTimeInterval(-30 * 60), kind: .high, heightFeet: 2.5)
        ]
        let flatRange = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .redfish,
            tideEvents: flatHeightEvents,
            now: now
        ).factors.first { $0.kind == .tide }!.raw

        #expect(base > flatRange)
        #expect(base - flatRange <= 0.08)
    }

    @Test
    func tideLabelDescribesFutureTurn() {
        let now = Date()
        let future = TideEvent(time: now.addingTimeInterval(45 * 60), kind: .high, heightFeet: 2.3)
        let farPast = TideEvent(time: now.addingTimeInterval(-5 * 3600), kind: .low, heightFeet: 0.4)

        let detail = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .redfish,
            tideEvents: [farPast, future],
            now: now
        ).factors.first { $0.kind == .tide }!.detail

        #expect(detail.contains("Next tide in 45 min"), "Detail was: \(detail)")
    }

    @Test
    func tideLabelDescribesPastTurn() {
        let now = Date()
        let past = TideEvent(time: now.addingTimeInterval(-90 * 60), kind: .low, heightFeet: 0.5)
        let farFuture = TideEvent(time: now.addingTimeInterval(5 * 3600), kind: .high, heightFeet: 3.8)

        let detail = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .redfish,
            tideEvents: [past, farFuture],
            now: now
        ).factors.first { $0.kind == .tide }!.detail

        #expect(detail.contains("Last tide 2 hr ago"), "Detail was: \(detail)")
    }

    @Test
    func majorWindowBeatsMinorAtSameProximity() {
        let now = Date()
        let major = BiteWindow(period: .major, peak: now, cause: "Moon overhead")
        let minor = BiteWindow(period: .minor, peak: now, cause: "Moonrise")

        let majorRaw = FishingScorer.score(
            moonPhase: .full,
            activeWindow: major,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .bass,
            now: now
        ).factors.first { $0.kind == .solunar }!.raw

        let minorRaw = FishingScorer.score(
            moonPhase: .full,
            activeWindow: minor,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .bass,
            now: now
        ).factors.first { $0.kind == .solunar }!.raw

        #expect(majorRaw > minorRaw)
    }

    @Test
    func windIsSmoothAcross13And19Thresholds() {
        let a = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 12.9,
            species: .bass
        ).factors.first { $0.kind == .wind }!.raw

        let b = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 13.1,
            species: .bass
        ).factors.first { $0.kind == .wind }!.raw

        let c = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 18.9,
            species: .bass
        ).factors.first { $0.kind == .wind }!.raw

        let d = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 19.1,
            species: .bass
        ).factors.first { $0.kind == .wind }!.raw

        #expect(abs(b - a) < 0.1)
        #expect(abs(d - c) < 0.1)
    }

    @Test
    func tideBoostIsCappedAtConfiguredMax() {
        let now = Date()
        // Place turns at +/-45 min so base isn't 1.0 and boost can express.
        let bigRange = [
            TideEvent(time: now.addingTimeInterval(-45 * 60), kind: .low, heightFeet: 0.0),
            TideEvent(time: now.addingTimeInterval(45 * 60), kind: .high, heightFeet: 12.0)
        ]
        let flatRange = [
            TideEvent(time: now.addingTimeInterval(-45 * 60), kind: .low, heightFeet: 2.5),
            TideEvent(time: now.addingTimeInterval(45 * 60), kind: .high, heightFeet: 2.5)
        ]

        let big = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .redfish,
            tideEvents: bigRange,
            now: now
        ).factors.first { $0.kind == .tide }!.raw

        let flat = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .redfish,
            tideEvents: flatRange,
            now: now
        ).factors.first { $0.kind == .tide }!.raw

        let delta = big - flat
        #expect(delta <= 0.08 + 0.0001)
        #expect(delta > 0)
    }

    @Test
    func windIsSmoothAcross2And25Thresholds() {
        // 2 mph threshold should be blended, not a cliff.
        let below2 = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 1.9,
            species: .bass
        ).factors.first { $0.kind == .wind }!.raw

        let above2 = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 2.1,
            species: .bass
        ).factors.first { $0.kind == .wind }!.raw

        #expect(abs(above2 - below2) < 0.1)

        // 25 mph threshold should also be blended.
        let below25 = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 24.9,
            species: .bass
        ).factors.first { $0.kind == .wind }!.raw

        let above25 = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 25.1,
            species: .bass
        ).factors.first { $0.kind == .wind }!.raw

        #expect(abs(above25 - below25) < 0.1)
    }

    @Test
    func solunarPhaseMattersAtSameWindow() {
        let now = Date()
        let window = BiteWindow(period: .major, peak: now, cause: "Moon overhead")

        let full = FishingScorer.score(
            moonPhase: .full,
            activeWindow: window,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .bass,
            now: now
        ).factors.first { $0.kind == .solunar }!.raw

        let quarter = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: window,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .bass,
            now: now
        ).factors.first { $0.kind == .solunar }!.raw

        #expect(full > quarter)
    }

    #if DEBUG
    @Test
    func debugDescribeListsFactors() {
        let now = Date()
        let text = FishingScorer.debugDescribe(
            moonPhase: .full,
            activeWindow: BiteWindow(period: .major, peak: now, cause: "Moon overhead"),
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .bass,
            tideEvents: [],
            now: now
        )
        #expect(text.contains("Solunar"))
        #expect(text.contains("Pressure"))
        #expect(text.contains("Wind"))
        #expect(text.contains("Season"))
    }
    #endif

    @Test
    func solunarIsNonIncreasingAsYouMoveAwayFromPeak() {
        let now = Date()
        let window = BiteWindow(period: .major, peak: now, cause: "Moon overhead")
        let offsets: [TimeInterval] = [0, 30 * 60, 60 * 60, 90 * 60, 120 * 60, 180 * 60, 240 * 60, 300 * 60]
        var values: [Double] = []
        for dt in offsets {
            let raw = FishingScorer.score(
                moonPhase: .full,
                activeWindow: nil,
                nextWindow: BiteWindow(period: .major, peak: now.addingTimeInterval(dt), cause: "Moon overhead"),
                pressureTendency: .steady,
                pressureChangePerHour: 0,
                windMph: 8,
                species: .bass,
                now: now
            ).factors.first { $0.kind == .solunar }!.raw
            values.append(raw)
        }
        for i in 0..<(values.count - 1) {
            #expect(values[i + 1] <= values[i] + 0.0001, "solunar raw should be non-increasing with distance; got \(values)")
        }
    }

    @Test
    func saltwaterOmitsTideFactorWhenNoEvents() {
        let score = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .redfish,
            tideEvents: [],
            now: Date()
        )
        let labels = Set(score.factors.map(\.label))
        #expect(!labels.contains("Tide"))
    }

    @Test
    func tideLabelRoundsToHoursAboveSixtyMinutes() {
        let now = Date()
        let events = [
            TideEvent(time: now.addingTimeInterval(75 * 60), kind: .high, heightFeet: 3.2),
            TideEvent(time: now.addingTimeInterval(-4 * 3600), kind: .low, heightFeet: 0.4)
        ]
        let detail = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .redfish,
            tideEvents: events,
            now: now
        ).factors.first { $0.kind == .tide }!.detail
        #expect(detail.contains("Next tide in 1 hr"), "Detail was: \(detail)")
    }

    @Test
    func pressureOrderingFallingSteadyRising() {
        let now = Date()
        let falling = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .falling,
            pressureChangePerHour: -0.8,
            windMph: 8,
            species: .bass,
            now: now
        ).factors.first { $0.kind == .pressure }!.raw

        let steady = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .bass,
            now: now
        ).factors.first { $0.kind == .pressure }!.raw

        let rising = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .rising,
            pressureChangePerHour: 0.8,
            windMph: 8,
            species: .bass,
            now: now
        ).factors.first { $0.kind == .pressure }!.raw

        #expect(falling > steady && steady > rising, "pressure ordering mismatch: falling=\(falling) steady=\(steady) rising=\(rising)")
    }

    @Test
    func seasonPeakBeatsOffPeak() {
        let peakDate = Self.fixedSpringDate // May 15, 2026 (bass peak per comment)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 15; comps.hour = 12
        let offDate = Calendar.current.date(from: comps)!

        let peak = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .bass,
            now: peakDate
        ).factors.first { $0.kind == .season }!.raw

        let off = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .bass,
            now: offDate
        ).factors.first { $0.kind == .season }!.raw

        #expect(peak == 1.0)
        #expect(peak > off)
    }

    @Test
    func windExtremesSaturate() {
        let calm = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 0,
            species: .bass
        ).factors.first { $0.kind == .wind }!.raw

        let storm = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 50,
            species: .bass
        ).factors.first { $0.kind == .wind }!.raw

        #expect(abs(calm - 0.55) < 0.0001)
        #expect(abs(storm - 0.20) < 0.0001)
    }

    @Test
    func tideLabelRoundsAtExactlySixtyMinutes() {
        let now = Date()
        let events = [
            TideEvent(time: now.addingTimeInterval(60 * 60), kind: .high, heightFeet: 3.0),
            TideEvent(time: now.addingTimeInterval(-6 * 3600), kind: .low, heightFeet: 0.2)
        ]
        let detail = FishingScorer.score(
            moonPhase: .firstQuarter,
            activeWindow: nil,
            nextWindow: nil,
            pressureTendency: .steady,
            pressureChangePerHour: 0,
            windMph: 8,
            species: .redfish,
            tideEvents: events,
            now: now
        ).factors.first { $0.kind == .tide }!.detail
        #expect(detail.contains("Next tide in 1 hr"), "Detail was: \(detail)")
    }
}
