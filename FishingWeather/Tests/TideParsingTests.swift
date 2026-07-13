import CoreLocation
import Foundation
import Testing
@testable import BiteCast

/// NOAA prediction parsing. Timestamps are requested and parsed in GMT so a
/// saved Gulf-coast spot renders correctly from any device timezone.
@Suite("TideService parsing")
struct TideParsingTests {
    private static var gmtCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }

    @Test
    func timestampsParseAsGMT() throws {
        let json = #"{"predictions": [{"t": "2026-06-15 08:24", "v": "1.352", "type": "H"}]}"#
        let points = try TideService.parsePredictions(Data(json.utf8))

        let expected = Self.gmtCalendar.date(
            from: DateComponents(year: 2026, month: 6, day: 15, hour: 8, minute: 24)
        )
        #expect(points.count == 1)
        #expect(points.first?.time == expected)
        #expect(points.first?.kind == .high)
        #expect(points.first?.heightFeet == 1.352)
    }

    @Test
    func hourlySamplesHaveNoKind() throws {
        let json = #"{"predictions": [{"t": "2026-06-15 09:00", "v": "0.8"}]}"#
        let points = try TideService.parsePredictions(Data(json.utf8))
        #expect(points.first?.kind == nil)
    }

    @Test
    func lowTideParsesAsLow() throws {
        let json = #"{"predictions": [{"t": "2026-06-15 14:41", "v": "-0.12", "type": "L"}]}"#
        let points = try TideService.parsePredictions(Data(json.utf8))
        #expect(points.first?.kind == .low)
        #expect(points.first?.heightFeet == -0.12)
    }

    @Test
    func noaaErrorEnvelopeSurfacesItsMessage() {
        let json = #"{"error": {"message": "No Predictions data was found."}}"#
        #expect(throws: (any Error).self) {
            try TideService.parsePredictions(Data(json.utf8))
        }
    }

    @Test("Day slices use the forecast calendar instead of the device day")
    func daySlicesUseForecastCalendar() throws {
        let referenceDate = try #require(Self.gmtCalendar.date(
            from: DateComponents(year: 2030, month: 7, day: 14, hour: 12)
        ))
        let boundaryDate = try #require(Self.gmtCalendar.date(
            from: DateComponents(year: 2030, month: 7, day: 14, hour: 4, minute: 30)
        ))
        let sharedDate = try #require(Self.gmtCalendar.date(
            from: DateComponents(year: 2030, month: 7, day: 14, hour: 15)
        ))
        let events = [
            TideEvent(time: boundaryDate, kind: .high, heightFeet: 3.2),
            TideEvent(time: sharedDate, kind: .low, heightFeet: 0.4),
        ]
        let samples = [
            TideSample(time: boundaryDate, heightFeet: 3.2),
            TideSample(time: sharedDate, heightFeet: 0.4),
        ]
        let newYork = Self.calendar(timeZoneIdentifier: "America/New_York")
        let honolulu = Self.calendar(timeZoneIdentifier: "Pacific/Honolulu")

        #expect(
            TideService.events(
                in: events,
                on: referenceDate,
                calendar: newYork
            ).map(\.time) == [boundaryDate, sharedDate]
        )
        #expect(
            TideService.events(
                in: events,
                on: referenceDate,
                calendar: honolulu
            ).map(\.time) == [sharedDate]
        )
        #expect(
            TideService.samples(
                in: samples,
                on: referenceDate,
                calendar: newYork
            ).map(\.time) == [boundaryDate, sharedDate]
        )
        #expect(
            TideService.samples(
                in: samples,
                on: referenceDate,
                calendar: honolulu
            ).map(\.time) == [sharedDate]
        )
    }

    @Test("One retained range serves a full next day but rejects a padded partial day")
    func retainedRangeServesNextDay() throws {
        let firstDay = try #require(Self.gmtCalendar.date(
            from: DateComponents(year: 2030, month: 7, day: 14, hour: 12)
        ))
        let nextDay = try #require(Self.gmtCalendar.date(
            byAdding: .day,
            value: 1,
            to: firstDay
        ))
        let partialDay = try #require(Self.gmtCalendar.date(
            byAdding: .day,
            value: 2,
            to: firstDay
        ))
        let firstEvent = TideEvent(
            time: firstDay,
            kind: .high,
            heightFeet: 3.4
        )
        let nextEvent = TideEvent(
            time: nextDay,
            kind: .low,
            heightFeet: 0.5
        )
        let firstSample = TideSample(time: firstDay, heightFeet: 3.4)
        let nextSample = TideSample(time: nextDay, heightFeet: 0.5)
        let partialSample = TideSample(time: partialDay, heightFeet: 1.1)
        let events = [firstEvent, nextEvent]
        let samples = [firstSample, nextSample, partialSample]
        let newYork = Self.calendar(timeZoneIdentifier: "America/New_York")
        let requestRange = TideService.requestDateRange(
            containing: firstDay,
            calendar: newYork
        )

        #expect(TideService.hasPredictions(
            events: events,
            samples: samples,
            on: nextDay,
            calendar: Self.gmtCalendar
        ))
        #expect(
            TideService.events(
                in: events,
                on: nextDay,
                calendar: Self.gmtCalendar
            ) == [nextEvent]
        )
        #expect(
            TideService.samples(
                in: samples,
                on: nextDay,
                calendar: Self.gmtCalendar
            ) == [nextSample]
        )
        #expect(TideService.coversFullDay(
            requestRange.coverage,
            containing: nextDay,
            calendar: newYork
        ))
        #expect(!TideService.coversFullDay(
            requestRange.coverage,
            containing: partialDay,
            calendar: newYork
        ))
        #expect(TideService.hasPredictions(
            events: events,
            samples: samples,
            on: partialDay,
            calendar: newYork
        ))
    }

    @Test("Tide data keys include the forecast timezone and local day")
    func dataKeysUseForecastCalendar() throws {
        let location = CLLocation(latitude: 27.7634, longitude: -82.6403)
        let referenceDate = try #require(Self.gmtCalendar.date(
            from: DateComponents(year: 2030, month: 7, day: 14, hour: 3, minute: 30)
        ))
        let newYork = Self.calendar(timeZoneIdentifier: "America/New_York")
        let london = Self.calendar(timeZoneIdentifier: "Europe/London")

        let newYorkKey = TideService.dataKey(
            location,
            date: referenceDate,
            calendar: newYork
        )
        let londonKey = TideService.dataKey(
            location,
            date: referenceDate,
            calendar: london
        )

        #expect(newYorkKey != londonKey)
        #expect(newYorkKey.contains("America/New_York-20300713"))
        #expect(londonKey.contains("Europe/London-20300714"))
    }

    @Test("NOAA request days cover adjacent forecast-local days at UTC plus fourteen")
    func requestDaysCoverForecastLocalRange() throws {
        let referenceDate = try #require(Self.gmtCalendar.date(
            from: DateComponents(year: 2030, month: 7, day: 14)
        ))
        let kiritimati = Self.calendar(timeZoneIdentifier: "Pacific/Kiritimati")

        let localRange = TideService.requestDateRange(
            containing: referenceDate,
            calendar: kiritimati
        )
        let gmtRange = TideService.requestDateRange(
            containing: referenceDate,
            calendar: Self.gmtCalendar
        )

        #expect(localRange.beginDate == "20300712")
        #expect(localRange.endDate == "20300715")
        #expect(gmtRange.beginDate == "20300713")
        #expect(gmtRange.endDate == "20300715")
    }

    @Test("Weekly tide groups use the forecast calendar's day boundaries")
    func weeklyGroupsUseForecastCalendar() throws {
        let boundaryDate = try #require(Self.gmtCalendar.date(
            from: DateComponents(year: 2030, month: 7, day: 14, hour: 4, minute: 30)
        ))
        let sharedDate = try #require(Self.gmtCalendar.date(
            from: DateComponents(year: 2030, month: 7, day: 14, hour: 15)
        ))
        let boundaryEvent = TideEvent(
            time: boundaryDate,
            kind: .high,
            heightFeet: 3.2
        )
        let sharedEvent = TideEvent(
            time: sharedDate,
            kind: .low,
            heightFeet: 0.4
        )
        let events = [boundaryEvent, sharedEvent]
        let newYork = Self.calendar(timeZoneIdentifier: "America/New_York")
        let honolulu = Self.calendar(timeZoneIdentifier: "Pacific/Honolulu")

        let newYorkGroups = TideService.eventsByDay(events, calendar: newYork)
        let honoluluGroups = TideService.eventsByDay(events, calendar: honolulu)

        #expect(newYorkGroups[newYork.startOfDay(for: boundaryDate)] == events)
        #expect(honoluluGroups[honolulu.startOfDay(for: boundaryDate)] == [boundaryEvent])
        #expect(honoluluGroups[honolulu.startOfDay(for: sharedDate)] == [sharedEvent])
    }

    private static func calendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        return calendar
    }
}
