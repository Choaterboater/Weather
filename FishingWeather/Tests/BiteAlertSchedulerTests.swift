import Foundation
import Testing
@testable import BiteCast

@Suite("BiteAlertScheduler")
struct BiteAlertSchedulerTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let enabled = AlertPreferences(enabled: true, minScore: 70,
                                           leadMinutes: 45, maxAlerts: 5)

    private func window(hoursFromNow: Double, score: Int,
                        confidence: ScoredWindow.Confidence = .high,
                        period: BitePeriod = .major) -> ScoredWindow {
        let start = now.addingTimeInterval(hoursFromNow * 3600)
        return ScoredWindow(
            date: start, start: start, end: start.addingTimeInterval(3600),
            score: score, confidence: confidence, period: period,
            factors: ["Major window", "Falling pressure"], species: .redfish
        )
    }

    private func outlook(_ windows: [ScoredWindow]) -> WeekOutlook {
        WeekOutlook(locationName: "Fort De Soto", generatedAt: now, windows: windows)
    }

    @Test("Disabled preferences schedule nothing")
    func disabledYieldsNoAlerts() {
        var prefs = enabled; prefs.enabled = false
        let alerts = BiteAlertScheduler.plan(
            from: outlook([window(hoursFromNow: 5, score: 90)]), preferences: prefs, now: now)
        #expect(alerts.isEmpty)
    }

    @Test("Only windows at or above the min score alert")
    func filtersBelowMinScore() {
        let alerts = BiteAlertScheduler.plan(from: outlook([
            window(hoursFromNow: 5, score: 60),
            window(hoursFromNow: 6, score: 85),
        ]), preferences: enabled, now: now)
        #expect(alerts.count == 1)
        #expect(alerts.first?.score == 85)
    }

    @Test("Low-confidence windows are excluded")
    func onlyHighConfidence() {
        let alerts = BiteAlertScheduler.plan(from: outlook([
            window(hoursFromNow: 5, score: 90, confidence: .low),
        ]), preferences: enabled, now: now)
        #expect(alerts.isEmpty)
    }

    @Test("Fire date is the lead time before the window start")
    func fireDateIsLeadBeforeStart() {
        let w = window(hoursFromNow: 5, score: 90)
        let alerts = BiteAlertScheduler.plan(from: outlook([w]), preferences: enabled, now: now)
        #expect(alerts.first?.fireDate == w.start.addingTimeInterval(-45 * 60))
    }

    @Test("Windows whose lead time already passed are skipped")
    func excludesPastFireDates() {
        // 30 min out, but the 45-min lead puts the fire date in the past.
        let alerts = BiteAlertScheduler.plan(
            from: outlook([window(hoursFromNow: 0.5, score: 90)]), preferences: enabled, now: now)
        #expect(alerts.isEmpty)
    }

    @Test("Output is capped and sorted by fire date, keeping the soonest")
    func cappedAndSorted() {
        let hours: [Double] = [8, 3, 11, 5, 2, 9]
        let windows = hours.map { window(hoursFromNow: $0, score: 80) }
        var prefs = enabled; prefs.maxAlerts = 3
        let alerts = BiteAlertScheduler.plan(from: outlook(windows), preferences: prefs, now: now)
        #expect(alerts.count == 3)
        #expect(alerts.map(\.fireDate) == alerts.map(\.fireDate).sorted())
        #expect(alerts.first?.windowStart == now.addingTimeInterval(2 * 3600))
    }
}
