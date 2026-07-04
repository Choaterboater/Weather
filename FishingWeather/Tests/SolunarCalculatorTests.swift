import Foundation
import Testing
@testable import BiteCast

/// Characterization tests for the solunar window math that feeds bite windows,
/// notifications, and 25% of the fishing score.
@Suite("SolunarCalculator")
struct SolunarCalculatorTests {
    private static let halfLunarDay: TimeInterval = 12 * 3600 + 25 * 60

    /// June 15, 2026 in the device calendar — no DST transition anywhere that day.
    private static func date(hour: Int, minute: Int = 0, dayOffset: Int = 0) -> Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 6, day: 15 + dayOffset, hour: hour, minute: minute)
        )!
    }

    @Test
    func riseAndSetProduceFourSortedWindows() {
        let windows = SolunarCalculator.windows(
            moonrise: Self.date(hour: 6, minute: 30),
            moonset: Self.date(hour: 20, minute: 10),
            on: Self.date(hour: 12)
        )
        #expect(windows.count == 4)
        #expect(windows.map(\.peak) == windows.map(\.peak).sorted())
        #expect(windows.filter { $0.period == .major }.count == 2)
        #expect(windows.filter { $0.period == .minor }.count == 2)
    }

    @Test
    func overheadTransitIsTheRiseSetMidpoint() {
        let rise = Self.date(hour: 6)
        let set = Self.date(hour: 20)
        let windows = SolunarCalculator.windows(moonrise: rise, moonset: set, on: Self.date(hour: 12))
        let overhead = windows.first { $0.cause == "Moon overhead" }
        #expect(overhead?.peak == Self.date(hour: 13))
    }

    @Test
    func underfootPrefersTheSameCalendarDay() {
        // Overhead 18:30 → earlier transit 06:05 falls on the same day → picked.
        let windows = SolunarCalculator.windows(
            moonrise: Self.date(hour: 14),
            moonset: Self.date(hour: 23),
            on: Self.date(hour: 12)
        )
        let underfoot = windows.first { $0.cause == "Moon underfoot" }
        #expect(underfoot?.peak == Self.date(hour: 6, minute: 5))
    }

    @Test
    func underfootFallsForwardWhenTheEarlierTransitWasYesterday() {
        // Overhead 05:00 → earlier transit 16:35 *yesterday* → the later one wins.
        let windows = SolunarCalculator.windows(
            moonrise: Self.date(hour: 0, minute: 30),
            moonset: Self.date(hour: 9, minute: 30),
            on: Self.date(hour: 12)
        )
        let underfoot = windows.first { $0.cause == "Moon underfoot" }
        #expect(underfoot?.peak == Self.date(hour: 17, minute: 25))
    }

    @Test
    func moonsetBeforeMoonriseEstimatesOverheadFromRiseAlone() {
        // Set at 08:00 belongs to the previous up-period; overhead should be
        // rise + quarter lunar day, not a midpoint that overshoots.
        let rise = Self.date(hour: 22)
        let windows = SolunarCalculator.windows(
            moonrise: rise,
            moonset: Self.date(hour: 8),
            on: Self.date(hour: 12)
        )
        let overhead = windows.first { $0.cause == "Moon overhead" }
        #expect(overhead?.peak == rise.addingTimeInterval(Self.halfLunarDay / 2))
    }

    @Test
    func onlyMoonriseYieldsRiseAndOverheadWhenUnderfootIsOffDay() {
        // Overhead ~12:12 → underfoot candidates fall on adjacent days and are omitted.
        let windows = SolunarCalculator.windows(
            moonrise: Self.date(hour: 6),
            moonset: nil,
            on: Self.date(hour: 12)
        )
        #expect(windows.count == 2)
        #expect(windows.filter { $0.period == .minor }.count == 1)
        #expect(windows.filter { $0.cause == "Moon underfoot" }.isEmpty)
    }

    @Test
    func underfootOmittedWhenNeitherCandidateIsToday() {
        // Overhead at 12:00 → earlier 23:35 yesterday, later 00:25 tomorrow.
        let windows = SolunarCalculator.windows(
            moonrise: Self.date(hour: 5, minute: 30),
            moonset: Self.date(hour: 18, minute: 30),
            on: Self.date(hour: 12)
        )
        let underfoot = windows.first { $0.cause == "Moon underfoot" }
        #expect(underfoot == nil)
        #expect(windows.contains { $0.cause == "Moon overhead" })
    }

    @Test
    func noMoonDataYieldsNoWindows() {
        let windows = SolunarCalculator.windows(moonrise: nil, moonset: nil, on: Self.date(hour: 12))
        #expect(windows.isEmpty)
    }
}
