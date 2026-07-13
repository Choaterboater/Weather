import Foundation
import Testing
@testable import BiteCast

@Suite("Tide card presentation")
struct TideCardPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Chart focuses on the displayed tide-event window")
    func chartUsesDisplayedEventsInsteadOfAllSamples() throws {
        let events = [
            TideEvent(time: now, kind: .high, heightFeet: 3.6),
            TideEvent(time: now.addingTimeInterval(6 * 3_600), kind: .low, heightFeet: 0.7),
            TideEvent(time: now.addingTimeInterval(12 * 3_600), kind: .high, heightFeet: 3.6),
            TideEvent(time: now.addingTimeInterval(18 * 3_600), kind: .low, heightFeet: 0.7),
        ]
        let samples = (-12...60).map { hour in
            TideSample(
                time: now.addingTimeInterval(Double(hour) * 3_600),
                heightFeet: Double(hour)
            )
        }

        let domain = try #require(
            TideCard.visibleChartDomain(events: events, samples: samples, now: now)
        )

        #expect(domain.lowerBound == now.addingTimeInterval(-3 * 3_600))
        #expect(domain.upperBound == now.addingTimeInterval(21 * 3_600))
        #expect(TideCard.visibleSamples(samples, in: domain).count == 25)
        #expect(domain.upperBound.timeIntervalSince(domain.lowerBound) == 24 * 3_600)
    }

    @Test("Chart uses four inset, evenly spaced time labels")
    func chartTicksStayInsideDomain() throws {
        let domain = now...now.addingTimeInterval(24 * 3_600)
        let ticks = TideCard.chartTickDates(in: domain)

        #expect(ticks.count == 4)
        #expect(ticks.allSatisfy { $0 > domain.lowerBound && $0 < domain.upperBound })
        #expect(ticks[1].timeIntervalSince(ticks[0]) == 6 * 3_600)
        #expect(ticks[2].timeIntervalSince(ticks[1]) == 6 * 3_600)
        #expect(ticks[3].timeIntervalSince(ticks[2]) == 6 * 3_600)
    }

    @Test("Now marker only appears inside the focused domain")
    func nowMarkerHonorsFocusedDomain() {
        let domain = now...now.addingTimeInterval(24 * 3_600)

        #expect(TideCard.shouldShowNow(now, in: domain))
        #expect(!TideCard.shouldShowNow(now.addingTimeInterval(-1), in: domain))
        #expect(!TideCard.shouldShowNow(now.addingTimeInterval(25 * 3_600), in: domain))
    }

    @Test("Axis labels use compact localized hours without minutes")
    func compactAxisTimeLabel() {
        let label = TideCard.chartTimeLabel(
            now,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(!label.contains(":"))
        #expect(label.contains("AM") || label.contains("PM"))
    }
}
