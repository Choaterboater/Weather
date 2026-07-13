import Foundation
import Testing
@testable import BiteCast

@Suite("DailyForecastView day labels")
struct DailyForecastViewTests {
    @Test("First forecast day is a weekday when it is tomorrow")
    func firstForecastDayTomorrowIsNotToday() throws {
        let now = try date("2026-07-13T15:00:00Z")
        let tomorrow = try date("2026-07-14T15:00:00Z")

        let label = DailyForecastView.dayLabel(
            for: tomorrow,
            now: now,
            timeZoneIdentifier: "America/Chicago",
            locale: Locale(identifier: "en_US")
        )

        #expect(label == "Tue")
    }

    @Test("UTC rollover still labels the forecast timezone's current day Today")
    func utcRolloverUsesForecastTimeZoneCalendarDay() throws {
        let now = try date("2026-07-14T00:30:00Z")
        let sameLosAngelesDay = try date("2026-07-13T08:00:00Z")

        let label = DailyForecastView.dayLabel(
            for: sameLosAngelesDay,
            now: now,
            timeZoneIdentifier: "America/Los_Angeles",
            locale: Locale(identifier: "en_US")
        )

        #expect(label == "Today")
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
