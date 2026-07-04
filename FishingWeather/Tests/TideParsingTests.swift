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
}
