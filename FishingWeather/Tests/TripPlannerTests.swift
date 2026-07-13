import CoreLocation
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

        #expect(conditions.tendency == nil)
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

    @Test("Forecast calendar uses the snapshot timezone")
    func forecastCalendarUsesSnapshotTimeZone() throws {
        let snapshot = Self.makeSnapshot(
            timeZoneIdentifier: "Pacific/Kiritimati",
            day: try #require(Self.utcCalendar.date(
                from: DateComponents(year: 2030, month: 7, day: 14)
            ))
        )

        let calendar = TripForecastLoader.forecastCalendar(for: snapshot)

        #expect(calendar.timeZone.identifier == "Pacific/Kiritimati")
    }

    @Test("Trip planner labels use the forecast timezone")
    func tripPlannerLabelsUseForecastTimeZone() throws {
        let instant = try #require(Self.utcCalendar.date(
            from: DateComponents(year: 2030, month: 7, day: 14, hour: 2, minute: 30)
        ))
        let honolulu = try #require(TimeZone(identifier: "Pacific/Honolulu"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let locale = Locale(identifier: "en_US_POSIX")

        let honoluluTime = TripPlannerDateFormatting.timeRange(
            from: instant,
            to: instant.addingTimeInterval(3_600),
            timeZone: honolulu,
            locale: locale
        )
        let tokyoTime = TripPlannerDateFormatting.timeRange(
            from: instant,
            to: instant.addingTimeInterval(3_600),
            timeZone: tokyo,
            locale: locale
        )
        let honoluluDay = TripPlannerDateFormatting.fullDate(
            instant,
            timeZone: honolulu,
            locale: locale
        )
        let tokyoDay = TripPlannerDateFormatting.fullDate(
            instant,
            timeZone: tokyo,
            locale: locale
        )

        #expect(honoluluTime != tokyoTime)
        #expect(honoluluDay != tokyoDay)
    }

    @MainActor
    @Test("Trip loader groups planned windows on the snapshot-local day")
    func tripLoaderUsesSnapshotCalendar() async throws {
        let referenceDate = try #require(Self.utcCalendar.date(
            from: DateComponents(year: 2030, month: 7, day: 14, hour: 0, minute: 30)
        ))
        let snapshot = Self.makeSnapshot(
            timeZoneIdentifier: "Pacific/Kiritimati",
            day: referenceDate
        )
        let calendar = TripForecastLoader.forecastCalendar(for: snapshot)
        let loader = TripForecastLoader()

        let outlook = await loader.load(
            for: CLLocation(latitude: 1.8721, longitude: -157.4278),
            species: .bass,
            locationName: "Kiritimati",
            snapshot: snapshot
        )

        let expectedDay = calendar.startOfDay(for: referenceDate)
        let unwrapped = try #require(outlook)
        #expect(!unwrapped.windows.isEmpty)
        #expect(unwrapped.windows.allSatisfy { $0.date == expectedDay })
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

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func makeSnapshot(
        timeZoneIdentifier: String,
        day: Date
    ) -> WeatherSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        let dayStart = calendar.startOfDay(for: day)
        let astronomy = AstronomySnapshot(
            sunrise: dayStart.addingTimeInterval(6 * 3_600),
            sunset: dayStart.addingTimeInterval(18 * 3_600),
            moonrise: dayStart.addingTimeInterval(7 * 3_600),
            moonset: dayStart.addingTimeInterval(19 * 3_600),
            moonTransit: dayStart.addingTimeInterval(13 * 3_600),
            moonPhaseFraction: 0.5
        )
        let wind = WindSnapshot(
            directionDegrees: 180,
            speedMetersPerSecond: 3,
            gustMetersPerSecond: nil
        )
        return WeatherSnapshot(
            coordinate: WeatherCoordinate(latitude: 1.8721, longitude: -157.4278),
            timeZoneIdentifier: timeZoneIdentifier,
            current: CurrentConditionsSnapshot(
                date: day,
                temperatureCelsius: 27,
                apparentTemperatureCelsius: 28,
                dewPointCelsius: 22,
                humidityFraction: 0.7,
                pressureHPa: 1_012,
                visibilityMeters: 16_000,
                uvIndex: 5,
                conditionText: "Clear",
                symbolName: "sun.max",
                wind: wind
            ),
            hourly: [],
            daily: [DailyWeatherPoint(
                date: day,
                lowCelsius: 24,
                highCelsius: 29,
                precipitationChance: 0.1,
                conditionText: "Clear",
                symbolName: "sun.max",
                windMetersPerSecond: 3,
                windPeakMetersPerSecond: nil,
                astronomy: astronomy
            )],
            alerts: [],
            astronomy: astronomy,
            provenance: WeatherProvenance(
                source: .weatherKit,
                fetchedAt: day,
                isFallback: false,
                attribution: "WeatherKit"
            )
        )
    }
}
