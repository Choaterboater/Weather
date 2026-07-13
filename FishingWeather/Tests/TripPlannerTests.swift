import Foundation
import Testing
@testable import BiteCast

@Suite("TripPlanner")
struct TripPlannerTests {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeDay(_ offsetDays: Int) -> DayForecastInput {
        let dayStart = cal.date(
            byAdding: .day,
            value: offsetDays,
            to: cal.startOfDay(for: now)
        )!
        return DayForecastInput(
            date: dayStart,
            moonrise: dayStart.addingTimeInterval(6 * 3_600),
            moonset: dayStart.addingTimeInterval(18 * 3_600),
            moonPhase: .full,
            dailyWindMph: 8
        )
    }

    private var hourly: [HourlyWeatherPoint] {
        (0..<48).map { index in
            makeHour(
                date: now.addingTimeInterval(Double(index) * 3_600),
                pressureHPa: 1_016 - Double(index) * 0.1
            )
        }
    }

    @Test("Daily conversion uses astronomy and sustained wind before peak")
    func dailyConversionUsesCanonicalFields() throws {
        let date = cal.startOfDay(for: now)
        let astronomy = AstronomySnapshot(
            sunrise: date.addingTimeInterval(6 * 3_600),
            sunset: date.addingTimeInterval(18 * 3_600),
            moonrise: date.addingTimeInterval(7 * 3_600),
            moonset: date.addingTimeInterval(19 * 3_600),
            moonTransit: date.addingTimeInterval(13 * 3_600),
            moonPhaseFraction: 0.5
        )
        let sustained = dailyPoint(
            date: date,
            wind: 4,
            peak: 9,
            astronomy: astronomy
        )
        let peakOnly = dailyPoint(
            date: date,
            wind: nil,
            peak: 9,
            astronomy: astronomy
        )
        let missing = dailyPoint(
            date: date,
            wind: nil,
            peak: nil,
            astronomy: astronomy
        )

        let sustainedInput = TripForecastLoader.dayInput(from: sustained)
        let peakInput = TripForecastLoader.dayInput(from: peakOnly)
        let missingInput = TripForecastLoader.dayInput(from: missing)

        #expect(sustainedInput.moonrise == astronomy.moonrise)
        #expect(sustainedInput.moonset == astronomy.moonset)
        #expect(sustainedInput.moonPhase == .full)
        #expect(abs((sustainedInput.dailyWindMph ?? 0) - 8.94775) < 0.001)
        #expect(abs((peakInput.dailyWindMph ?? 0) - 20.1324) < 0.001)
        #expect(missingInput.dailyWindMph == nil)
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

    @Test("Missing hourly pressure keeps wind confidence without inventing pressure")
    func missingHourlyPressureIsNeutral() throws {
        let points = [
            makeHour(date: now, pressureHPa: nil),
            makeHour(date: now.addingTimeInterval(3_600), pressureHPa: nil),
        ]

        let conditions = try #require(
            TripPlanner.conditions(at: now, hourly: points)
        )

        #expect(conditions.tendency == .steady)
        #expect(conditions.changePerHour == nil)
        #expect(abs(conditions.windMph - 8) < 0.001)
    }

    @Test("Missing daily wind stays missing in a low-confidence outlook")
    func missingDailyWindIsHandledWithoutFabrication() {
        let dayStart = cal.startOfDay(for: now)
        let day = DayForecastInput(
            date: dayStart,
            moonrise: dayStart.addingTimeInterval(6 * 3_600),
            moonset: dayStart.addingTimeInterval(18 * 3_600),
            moonPhase: .full,
            dailyWindMph: nil
        )

        let outlook = TripPlanner.outlook(
            days: [day],
            hourly: [],
            tidesByDay: [:],
            species: .bass,
            locationName: "Lake",
            now: now,
            maxWindows: 100
        )

        #expect(!outlook.isEmpty)
        #expect(outlook.windows.allSatisfy { $0.confidence == .low })
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
            date: cal.startOfDay(for: now),
            moonrise: nil,
            moonset: nil,
            moonPhase: .full,
            dailyWindMph: 8
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
        #expect(outlook.windows.allSatisfy {
            $0.factors.first?.hasSuffix("window") == true
        })
    }

    @Test("Only future windows are included")
    func onlyFutureWindows() {
        let midday = cal.date(
            byAdding: .hour,
            value: 12,
            to: cal.startOfDay(for: now)
        )!
        let outlook = TripPlanner.outlook(
            days: [makeDay(0)], hourly: hourly, tidesByDay: [:],
            species: .bass, locationName: "Lake", now: midday, maxWindows: 100
        )
        #expect(outlook.windows.allSatisfy { $0.end >= midday })
    }

    private func makeHour(
        date: Date,
        pressureHPa: Double?
    ) -> HourlyWeatherPoint {
        HourlyWeatherPoint(
            date: date,
            temperatureCelsius: 22.2,
            apparentTemperatureCelsius: nil,
            dewPointCelsius: nil,
            humidityFraction: nil,
            pressureHPa: pressureHPa,
            visibilityMeters: nil,
            uvIndex: nil,
            cloudCoverFraction: nil,
            precipitationChance: 0,
            precipitationMM: 0,
            conditionText: "Clear",
            symbolName: "sun.max",
            wind: WindSnapshot(
                directionDegrees: 180,
                speedMetersPerSecond: 8 * 0.44704,
                gustMetersPerSecond: nil
            )
        )
    }

    private func dailyPoint(
        date: Date,
        wind: Double?,
        peak: Double?,
        astronomy: AstronomySnapshot?
    ) -> DailyWeatherPoint {
        DailyWeatherPoint(
            date: date,
            lowCelsius: 20,
            highCelsius: 28,
            precipitationChance: 0.1,
            conditionText: "Clear",
            symbolName: "sun.max",
            windMetersPerSecond: wind,
            windPeakMetersPerSecond: peak,
            astronomy: astronomy
        )
    }
}
