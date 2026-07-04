import Foundation
import Testing
@testable import BiteCast

@Suite("TripPlanner")
struct TripPlannerTests {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// A day with a normal moonrise/moonset so the solunar calculator yields
    /// windows.
    private func makeDay(_ offsetDays: Int) -> DayForecastInput {
        let dayStart = cal.date(byAdding: .day, value: offsetDays,
                                to: cal.startOfDay(for: now))!
        return DayForecastInput(
            date: dayStart,
            moonrise: dayStart.addingTimeInterval(6 * 3600),
            moonset: dayStart.addingTimeInterval(18 * 3600),
            moonPhase: .full,
            dailyWindMph: 8
        )
    }

    /// 48 hours of hourly samples from `now` with a gently falling barometer.
    private var hourly: [HourSample] {
        (0..<48).map { i in
            HourSample(
                date: now.addingTimeInterval(Double(i) * 3600),
                temperature: 72,
                pressureHPa: 1016 - Double(i) * 0.1,
                precipChance: 0,
                windSpeedMph: 8,
                windGustMph: nil
            )
        }
    }

    @Test("No days yields an empty outlook")
    func emptyDaysYieldEmptyOutlook() {
        let outlook = TripPlanner.outlook(
            days: [], hourly: [], tidesByDay: [:],
            species: .bass, locationName: "Lake", now: now
        )
        #expect(outlook.isEmpty)
    }

    @Test("Windows are ranked best score first")
    func windowsSortedByScoreDescending() {
        let outlook = TripPlanner.outlook(
            days: (0..<3).map(makeDay), hourly: hourly, tidesByDay: [:],
            species: .bass, locationName: "Lake", now: now, maxWindows: 100
        )
        #expect(!outlook.windows.isEmpty)
        let scores = outlook.windows.map(\.score)
        #expect(scores == scores.sorted(by: >))
        #expect(outlook.windows.allSatisfy { (0...100).contains($0.score) })
    }

    @Test("Near days are high confidence, far days low")
    func confidenceMarkedByHourlyHorizon() {
        let outlook = TripPlanner.outlook(
            days: (0..<7).map(makeDay), hourly: hourly, tidesByDay: [:],
            species: .bass, locationName: "Lake", now: now, maxWindows: 100
        )
        #expect(outlook.windows.contains { $0.confidence == .high })
        #expect(outlook.windows.contains { $0.confidence == .low })
    }

    @Test("Output is capped at maxWindows")
    func capsAtMaxWindows() {
        let outlook = TripPlanner.outlook(
            days: (0..<7).map(makeDay), hourly: hourly, tidesByDay: [:],
            species: .bass, locationName: "Lake", now: now, maxWindows: 5
        )
        #expect(outlook.windows.count <= 5)
    }

    @Test("A day with no moon data contributes no windows and doesn't crash")
    func missingMoonDataYieldsNoWindows() {
        let day = DayForecastInput(
            date: cal.startOfDay(for: now), moonrise: nil, moonset: nil,
            moonPhase: .full, dailyWindMph: 8
        )
        let outlook = TripPlanner.outlook(
            days: [day], hourly: hourly, tidesByDay: [:],
            species: .bass, locationName: "Lake", now: now
        )
        #expect(outlook.isEmpty)
    }

    @Test("Every window's why-line leads with its solunar period")
    func factorsLeadWithPeriod() {
        let outlook = TripPlanner.outlook(
            days: [makeDay(0)], hourly: hourly, tidesByDay: [:],
            species: .bass, locationName: "Lake", now: now, maxWindows: 100
        )
        #expect(!outlook.windows.isEmpty)
        #expect(outlook.windows.allSatisfy { $0.factors.first?.hasSuffix("window") == true })
    }

    @Test("Only future windows are included")
    func onlyFutureWindows() {
        // `now` is midday, so this morning's windows are already past.
        let midday = cal.date(byAdding: .hour, value: 12, to: cal.startOfDay(for: now))!
        let outlook = TripPlanner.outlook(
            days: [makeDay(0)], hourly: hourly, tidesByDay: [:],
            species: .bass, locationName: "Lake", now: midday, maxWindows: 100
        )
        #expect(outlook.windows.allSatisfy { $0.end >= midday })
    }
}
