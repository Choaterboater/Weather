import Foundation
import Testing
@testable import BiteCast

@Suite("SeasonClosure")
struct SeasonClosureTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test
    func endDayIsClosedAtNoon() {
        let closure = SeasonClosure(start: "02-01", end: "02-28", label: "Closed in February")
        #expect(closure.contains(Self.date(year: 2026, month: 2, day: 28), calendar: Self.calendar))
        #expect(closure.contains(Self.date(year: 2026, month: 2, day: 1), calendar: Self.calendar))
        #expect(!closure.contains(Self.date(year: 2026, month: 3, day: 1), calendar: Self.calendar))
    }

    @Test
    func wrapAroundEndDayIsClosed() {
        let closure = SeasonClosure(start: "12-15", end: "01-31", label: "Closed Dec 15 – Jan 31")
        #expect(closure.contains(Self.date(year: 2026, month: 1, day: 31), calendar: Self.calendar))
        #expect(closure.contains(Self.date(year: 2026, month: 12, day: 15), calendar: Self.calendar))
        #expect(!closure.contains(Self.date(year: 2026, month: 2, day: 1), calendar: Self.calendar))
    }
}
