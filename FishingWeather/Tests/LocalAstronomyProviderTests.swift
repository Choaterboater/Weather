import CoreLocation
import Foundation
import Testing
@testable import BiteCast

@Suite("Local astronomy")
struct LocalAstronomyProviderTests {
    private static let solarTolerance: TimeInterval = 5 * 60
    private static let lunarTolerance: TimeInterval = 20 * 60
    private static let synodicMonthDays = 29.530588853
    private static let referenceNewMoonJulianDay = 2_451_550.25972
    private static let halfLunationJulianDay = 2_451_565.0250144265
    private static let julianDayAtUnixEpoch = 2_440_587.5
    private static let phaseTolerance = 1e-10

    @Test
    func returnsSolarAndMoonValues() {
        let value = snapshot(
            latitude: 30.2938,
            longitude: -86.0049,
            date: "2026-06-21T12:00:00Z",
            timeZone: "America/Chicago"
        )

        #expect(value.sunrise != nil)
        #expect(value.sunset != nil)
        #expect(value.moonrise != nil)
        #expect(value.moonset != nil)
        #expect(value.moonTransit != nil)
        #expect(value.moonPhaseFraction.map { (0...1).contains($0) } == true)
    }

    // Independent fixtures: U.S. Naval Observatory Astronomical Applications
    // Department, Complete Sun and Moon Data API v4.0.1, retrieved 2026-07-12.
    // Source URL: https://aa.usno.navy.mil/api/rstt/oneday?date=2026-06-21&coords=30.2938,-86.0049&tz=-6&dst=true
    // USNO returns CDT; Skyfield 1.54 + JPL DE440s agrees to the rounded minute.
    @Test
    func matchesUSNOFloridaFixture() {
        let value = snapshot(
            latitude: 30.2938,
            longitude: -86.0049,
            date: "2026-06-21T12:00:00Z",
            timeZone: "America/Chicago"
        )

        expect(value.sunrise, near: "2026-06-21T10:43:00Z", within: Self.solarTolerance)
        expect(value.sunset, near: "2026-06-22T00:49:00Z", within: Self.solarTolerance)
        expect(value.moonrise, near: "2026-06-21T17:38:00Z", within: Self.lunarTolerance)
        expect(value.moonset, near: "2026-06-21T05:16:00Z", within: Self.lunarTolerance)
        expect(value.moonTransit, near: "2026-06-21T23:45:00Z", within: Self.lunarTolerance)
    }

    // Source URL: https://aa.usno.navy.mil/api/rstt/oneday?date=2026-09-22&coords=44.9778,-93.2650&tz=-6&dst=true
    // USNO returns CDT; Skyfield 1.54 + JPL DE440s agrees to the rounded minute.
    @Test
    func matchesUSNOMinnesotaFixture() {
        let value = snapshot(
            latitude: 44.9778,
            longitude: -93.2650,
            date: "2026-09-22T12:00:00Z",
            timeZone: "America/Chicago"
        )

        expect(value.sunrise, near: "2026-09-22T12:00:00Z", within: Self.solarTolerance)
        expect(value.sunset, near: "2026-09-23T00:10:00Z", within: Self.solarTolerance)
        expect(value.moonrise, near: "2026-09-22T22:32:00Z", within: Self.lunarTolerance)
        expect(value.moonset, near: "2026-09-22T07:21:00Z", within: Self.lunarTolerance)
        expect(value.moonTransit, near: "2026-09-23T03:26:00Z", within: Self.lunarTolerance)
    }

    // Source URL: https://aa.usno.navy.mil/api/rstt/oneday?date=2026-09-22&coords=64.8378,-147.7164&tz=-9&dst=true
    // USNO returns AKDT; Skyfield 1.54 + JPL DE440s agrees to the rounded minute.
    @Test
    func matchesUSNOAlaskaFixture() {
        let value = snapshot(
            latitude: 64.8378,
            longitude: -147.7164,
            date: "2026-09-22T12:00:00Z",
            timeZone: "America/Anchorage"
        )

        expect(value.sunrise, near: "2026-09-22T15:35:00Z", within: Self.solarTolerance)
        expect(value.sunset, near: "2026-09-23T03:51:00Z", within: Self.solarTolerance)
        expect(value.moonrise, near: "2026-09-23T03:43:00Z", within: Self.lunarTolerance)
        expect(value.moonset, near: "2026-09-22T09:03:00Z", within: Self.lunarTolerance)
        expect(value.moonTransit, near: "2026-09-23T07:11:00Z", within: Self.lunarTolerance)
    }

    @Test
    func usesTheSuppliedCalendarDay() {
        let morning = snapshot(
            latitude: 30.2938,
            longitude: -86.0049,
            date: "2026-06-21T12:00:00Z",
            timeZone: "America/Chicago"
        )
        let lateEvening = snapshot(
            latitude: 30.2938,
            longitude: -86.0049,
            date: "2026-06-22T02:00:00Z",
            timeZone: "America/Chicago"
        )

        #expect(lateEvening.sunrise == morning.sunrise)
        #expect(lateEvening.sunset == morning.sunset)
        #expect(lateEvening.moonrise == morning.moonrise)
        #expect(lateEvening.moonset == morning.moonset)
        #expect(lateEvening.moonTransit == morning.moonTransit)
    }

    @Test
    func exactLocalMidnightUsesTheNewCalendarDay() {
        let midnight = snapshot(
            latitude: 34.0522,
            longitude: -118.2437,
            date: "2026-07-12T07:00:00Z",
            timeZone: "America/Los_Angeles"
        )
        let noon = snapshot(
            latitude: 34.0522,
            longitude: -118.2437,
            date: "2026-07-12T19:00:00Z",
            timeZone: "America/Los_Angeles"
        )

        #expect(midnight.sunrise == noon.sunrise)
        #expect(midnight.sunset == noon.sunset)
        #expect(midnight.moonrise == noon.moonrise)
        #expect(midnight.moonset == noon.moonset)
        #expect(midnight.moonTransit == noon.moonTransit)
    }

    @Test
    func repeatsExactlyForTheSameInputs() {
        let location = CLLocation(latitude: 44.9778, longitude: -93.2650)
        let date = Self.date("2026-09-22T12:00:00Z")
        let calendar = Self.calendar(timeZone: "America/Chicago")
        let provider = LocalAstronomyProvider()

        let first = provider.snapshot(for: location, date: date, calendar: calendar)
        let second = provider.snapshot(for: location, date: date, calendar: calendar)

        #expect(first == second)
    }

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity])
    func nonFiniteDateReturnsEmpty(timeIntervalSinceReferenceDate: Double) {
        let value = LocalAstronomyProvider().snapshot(
            for: CLLocation(latitude: 30.2938, longitude: -86.0049),
            date: Date(
                timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate
            ),
            calendar: Self.calendar(timeZone: "UTC")
        )

        #expect(value == AstronomySnapshot.empty)
    }

    @Test
    func phaseUsesTheDeclaredNewMoonEpoch() {
        let provider = LocalAstronomyProvider()
        let location = CLLocation(latitude: 30.2938, longitude: -86.0049)
        let calendar = Self.calendar(timeZone: "UTC")
        let newMoonDate = Self.date(
            julianDay: Self.referenceNewMoonJulianDay
        )
        let halfLunationDate = Self.date(
            julianDay: Self.halfLunationJulianDay
        )

        let newMoonPhase = provider.snapshot(
            for: location,
            date: newMoonDate,
            calendar: calendar
        ).moonPhaseFraction
        let halfLunationPhase = provider.snapshot(
            for: location,
            date: halfLunationDate,
            calendar: calendar
        ).moonPhaseFraction

        guard let newMoonPhase, let halfLunationPhase else {
            Issue.record("Expected phase values at the declared epoch")
            return
        }
        let newMoonCircularDistance = min(
            abs(newMoonPhase),
            abs(1 - newMoonPhase)
        )
        #expect(newMoonCircularDistance < Self.phaseTolerance)
        #expect(abs(halfLunationPhase - 0.5) < Self.phaseTolerance)
    }

    @Test
    func synodicPhaseRepeatsAfterOneMeanLunation() {
        let location = CLLocation(latitude: 30.2938, longitude: -86.0049)
        let date = Self.date("2026-06-21T12:00:00Z")
        let later = date.addingTimeInterval(Self.synodicMonthDays * 86_400)
        let calendar = Self.calendar(timeZone: "America/Chicago")
        let provider = LocalAstronomyProvider()

        let first = provider.snapshot(for: location, date: date, calendar: calendar)
        let second = provider.snapshot(for: location, date: later, calendar: calendar)

        guard let firstPhase = first.moonPhaseFraction,
              let secondPhase = second.moonPhaseFraction else {
            Issue.record("Expected synodic phase values")
            return
        }
        #expect(abs(firstPhase - secondPhase) < 1e-10)
    }

    @Test
    func polarNoSolarEventRemainsNil() {
        let value = snapshot(
            latitude: 89,
            longitude: 0,
            date: "2026-06-21T12:00:00Z",
            timeZone: "UTC"
        )

        #expect(value.sunrise == nil)
        #expect(value.sunset == nil)
    }

    // USNO AA API v4.0.1 reports a 45-minute solar window on this local day.
    // Both hourly endpoints remain below the horizon, so the coarse scan must
    // inspect inside the bin before refining the two crossings.
    // Source URL: https://aa.usno.navy.mil/api/rstt/oneday?date=2026-12-21&coords=67.3,-8&tz=0
    @Test
    func detectsShortSolarWindowInsideAnHourlyBin() {
        let value = snapshot(
            latitude: 67.3,
            longitude: -8,
            date: "2026-12-21T12:00:00Z",
            timeZone: "UTC"
        )

        expect(value.sunrise, near: "2026-12-21T12:08:00Z", within: Self.solarTolerance)
        expect(value.sunset, near: "2026-12-21T12:53:00Z", within: Self.solarTolerance)
    }

    // USNO reports the Moon continuously below the horizon in Fairbanks on
    // 2026-10-15. Local sampling must preserve the missing crossings as nil.
    @Test
    func lunarNoCrossingRemainsNil() {
        let value = snapshot(
            latitude: 64.8378,
            longitude: -147.7164,
            date: "2026-10-15T12:00:00Z",
            timeZone: "America/Anchorage"
        )

        #expect(value.moonrise == nil)
        #expect(value.moonset == nil)
        #expect(value.moonTransit != nil)
    }

    private func snapshot(
        latitude: Double,
        longitude: Double,
        date: String,
        timeZone: String
    ) -> AstronomySnapshot {
        LocalAstronomyProvider().snapshot(
            for: CLLocation(latitude: latitude, longitude: longitude),
            date: Self.date(date),
            calendar: Self.calendar(timeZone: timeZone)
        )
    }

    private func expect(
        _ actual: Date?,
        near expected: String,
        within tolerance: TimeInterval,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let actual else {
            Issue.record("Expected an astronomy event", sourceLocation: sourceLocation)
            return
        }

        let expected = Self.date(expected)
        #expect(
            abs(actual.timeIntervalSince(expected)) <= tolerance,
            "Expected \(actual) within \(tolerance) seconds of \(expected)",
            sourceLocation: sourceLocation
        )
    }

    private static func calendar(timeZone identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private static func date(julianDay: Double) -> Date {
        Date(
            timeIntervalSince1970: (julianDay - julianDayAtUnixEpoch) * 86_400
        )
    }
}
