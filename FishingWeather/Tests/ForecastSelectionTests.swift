import Foundation
import Testing
@testable import BiteCast

@Suite("Forecast selection")
struct ForecastSelectionTests {
    @Test func snapsToNearestHour() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let points = [0, 1, 2].map {
            ForecastPoint.fixture(
                date: start.addingTimeInterval(Double($0) * 3_600)
            )
        }

        let value = ForecastSelection.nearest(
            to: start.addingTimeInterval(2_000),
            in: points
        )

        #expect(value?.date == points[1].date)
    }

    @Test func exactTieChoosesEarlierHour() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let earlier = ForecastPoint.fixture(date: start)
        let later = ForecastPoint.fixture(date: start.addingTimeInterval(3_600))

        let value = ForecastSelection.nearest(
            to: start.addingTimeInterval(1_800),
            in: [later, earlier]
        )

        #expect(value?.date == earlier.date)
    }

    @Test func emptyReturnsNil() {
        #expect(ForecastSelection.nearest(to: .now, in: []) == nil)
    }

    @Test func rawDragOnlyChangesWhenTheSnappedHourChanges() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let points = [0, 1, 2].map {
            ForecastPoint.fixture(
                date: start.addingTimeInterval(Double($0) * 3_600)
            )
        }
        let current = points[1].date

        let sameHour = ForecastSelection.snappedDate(
            for: current.addingTimeInterval(200),
            current: current,
            in: points
        )
        let nextHour = ForecastSelection.snappedDate(
            for: current.addingTimeInterval(2_000),
            current: current,
            in: points
        )

        #expect(sameHour == current)
        #expect(nextHour == points[2].date)
    }

    @Test func absentRawSelectionDoesNotInitializeSharedState() {
        let point = ForecastPoint.fixture()

        let value = ForecastSelection.snappedDate(
            for: nil,
            current: nil,
            in: [point]
        )

        #expect(value == nil)
    }

    @Test func builderUsesFutureProviderHoursWithoutMutatingSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let hours = (-2..<52).map {
            HourlyWeatherPoint.fixture(
                date: now.addingTimeInterval(Double($0) * 3_600),
                temperatureCelsius: Double($0)
            )
        }
        let snapshot = WeatherSnapshot.fixture(now: now, hourly: hours)
        let original = snapshot

        let points = ForecastSeriesBuilder.build(
            weather: snapshot,
            tideSamples: [],
            species: .bass,
            weights: .standard,
            now: now
        )

        #expect(points.count == 48)
        #expect(points.first?.date == now)
        #expect(points.last?.date == now.addingTimeInterval(47 * 3_600))
        #expect(points.map(\.date) == points.map(\.date).sorted())
        #expect(snapshot == original)
        #expect(points.allSatisfy { $0.biteScore != nil })
    }

    @Test func builderInterpolatesTideHeightAndLabelsDirection() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let pointDate = now.addingTimeInterval(30 * 60)
        let snapshot = WeatherSnapshot.fixture(
            now: now,
            hourly: [.fixture(date: pointDate)]
        )
        let samples = [
            TideSample(time: now, heightFeet: 1),
            TideSample(time: now.addingTimeInterval(3_600), heightFeet: 3),
        ]

        let point = try #require(ForecastSeriesBuilder.build(
            weather: snapshot,
            tideSamples: samples,
            species: .redfish,
            weights: .standard,
            now: now
        ).first)

        #expect(abs((point.tideHeightFeet ?? 0) - 2) < 0.000_1)
        #expect(point.tidePhase == "Rising")
    }

    @Test func builderAttachesActiveSolunarWindowToTheSameHour() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let peak = now.addingTimeInterval(3_600)
        let snapshot = WeatherSnapshot.fixture(
            now: now,
            hourly: [.fixture(date: peak)],
            astronomy: AstronomySnapshot(
                sunrise: nil,
                sunset: nil,
                moonrise: peak,
                moonset: nil,
                moonTransit: nil,
                moonPhaseFraction: 0.5
            )
        )

        let point = try #require(ForecastSeriesBuilder.build(
            weather: snapshot,
            tideSamples: [],
            species: .bass,
            weights: .standard,
            now: now
        ).first)

        #expect(point.solunarWindow?.period == .minor)
        #expect(point.solunarWindow?.cause == "Moonrise")
        #expect(point.biteScore != nil)
    }

    @Test func builderUsesAstronomyForEachForecastDay() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let nextDayPeak = now.addingTimeInterval(25 * 3_600)
        let nextDayAstronomy = AstronomySnapshot(
            sunrise: nil,
            sunset: nil,
            moonrise: nextDayPeak,
            moonset: nil,
            moonTransit: nil,
            moonPhaseFraction: 0.5
        )
        let snapshot = WeatherSnapshot.fixture(
            now: now,
            hourly: [.fixture(date: nextDayPeak)],
            astronomy: .empty,
            daily: [
                .fixture(date: now, astronomy: .empty),
                .fixture(date: now.addingTimeInterval(24 * 3_600),
                         astronomy: nextDayAstronomy),
            ],
            timeZoneIdentifier: "UTC"
        )

        let point = try #require(ForecastSeriesBuilder.build(
            weather: snapshot,
            tideSamples: [],
            species: .bass,
            weights: .standard,
            now: now
        ).first)

        #expect(point.solunarWindow?.cause == "Moonrise")
    }

    @Test func builderDoesNotCarryTideScoreBeyondSampleCoverage() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let forecastDate = now.addingTimeInterval(6 * 3_600)
        let snapshot = WeatherSnapshot.fixture(
            now: now,
            hourly: [.fixture(date: forecastDate)]
        )
        let coveredTides = [
            TideSample(time: now, heightFeet: 1),
            TideSample(time: now.addingTimeInterval(3_600), heightFeet: 3),
            TideSample(time: now.addingTimeInterval(2 * 3_600), heightFeet: 1),
        ]

        let outsideCoverage = try #require(ForecastSeriesBuilder.build(
            weather: snapshot,
            tideSamples: coveredTides,
            species: .redfish,
            weights: .standard,
            now: now
        ).first)
        let withoutTides = try #require(ForecastSeriesBuilder.build(
            weather: snapshot,
            tideSamples: [],
            species: .redfish,
            weights: .standard,
            now: now
        ).first)

        #expect(outsideCoverage.tideHeightFeet == nil)
        #expect(outsideCoverage.tidePhase == nil)
        #expect(outsideCoverage.biteScore == withoutTides.biteScore)
    }

    @Test func nonFinitePressureScoresAsUnavailable() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let missing = WeatherSnapshot.fixture(
            now: now,
            hourly: [.fixture(date: now, pressureHPa: nil)]
        )
        let nonFinite = WeatherSnapshot.fixture(
            now: now,
            hourly: [.fixture(date: now, pressureHPa: .nan)]
        )

        let missingPoint = try #require(ForecastSeriesBuilder.build(
            weather: missing,
            tideSamples: [],
            species: .bass,
            now: now
        ).first)
        let nonFinitePoint = try #require(ForecastSeriesBuilder.build(
            weather: nonFinite,
            tideSamples: [],
            species: .bass,
            now: now
        ).first)

        #expect(nonFinitePoint.biteScore == missingPoint.biteScore)
    }

    @Test func duplicateProviderHoursProduceOneStablePoint() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = WeatherSnapshot.fixture(
            now: now,
            hourly: [
                .fixture(date: now, temperatureCelsius: 20),
                .fixture(date: now, temperatureCelsius: 21),
            ]
        )

        let points = ForecastSeriesBuilder.build(
            weather: snapshot,
            tideSamples: [],
            species: .bass,
            now: now
        )

        #expect(points.count == 1)
        #expect(points.first?.weather.temperatureCelsius == 20)
    }

    @Test func builderPopulatesTrustworthyMatrixInputs() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let selectedHour = now.addingTimeInterval(2 * 3_600)
        let sunrise = now.addingTimeInterval(-2 * 3_600)
        let sunset = now.addingTimeInterval(8 * 3_600)
        let snapshot = WeatherSnapshot.fixture(
            now: now,
            hourly: [
                .fixture(date: now, pressureHPa: 1_013),
                .fixture(date: selectedHour, pressureHPa: 1_011),
            ],
            astronomy: AstronomySnapshot(
                sunrise: sunrise,
                sunset: sunset,
                moonrise: nil,
                moonset: nil,
                moonTransit: nil,
                moonPhaseFraction: 0.5
            )
        )
        let tides = [
            TideSample(time: now, heightFeet: 1),
            TideSample(time: now.addingTimeInterval(3_600), heightFeet: 3),
            TideSample(time: selectedHour, heightFeet: 2),
            TideSample(time: now.addingTimeInterval(3 * 3_600), heightFeet: 1),
            TideSample(time: now.addingTimeInterval(4 * 3_600), heightFeet: 2),
        ]

        let point = try #require(ForecastSeriesBuilder.build(
            weather: snapshot,
            tideSamples: tides,
            species: .redfish,
            now: now
        ).first { $0.date == selectedHour })

        #expect(point.pressureTendency == .falling)
        #expect(point.moonPhase == .full)
        #expect(point.sunrise == sunrise)
        #expect(point.sunset == sunset)
        #expect(abs((point.tideRateFeetPerHour ?? 0) + 1) < 0.000_1)
        #expect(point.nextTideTurn?.kind == .low)
        #expect(point.nextTideTurn?.time == now.addingTimeInterval(3 * 3_600))
    }

    @Test func builderOmitsUnsupportedMatrixInputs() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = WeatherSnapshot.fixture(
            now: now,
            hourly: [.fixture(date: now, pressureHPa: nil)],
            astronomy: .empty
        )

        let point = try #require(ForecastSeriesBuilder.build(
            weather: snapshot,
            tideSamples: [],
            species: .bass,
            now: now
        ).first)

        #expect(point.pressureTendency == nil)
        #expect(point.moonPhase == nil)
        #expect(point.sunrise == nil)
        #expect(point.sunset == nil)
        #expect(point.tideRateFeetPerHour == nil)
        #expect(point.nextTideTurn == nil)
    }
}

private extension ForecastPoint {
    static func fixture(
        date: Date = Date(timeIntervalSince1970: 1_800_000_000),
        temperatureCelsius: Double = 20,
        pressureHPa: Double? = 1_013,
        visibilityMeters: Double? = 16_000,
        precipitationChance: Double? = 0,
        windSpeedMetersPerSecond: Double = 3,
        biteScore: Int? = 50,
        tideHeightFeet: Double? = nil,
        tidePhase: String? = nil,
        solunarWindow: BiteWindow? = nil,
        pressureTendency: PressureTendency? = nil,
        moonPhase: LunarPhase? = nil,
        sunrise: Date? = nil,
        sunset: Date? = nil,
        tideRateFeetPerHour: Double? = nil,
        nextTideTurn: TideEvent? = nil
    ) -> ForecastPoint {
        ForecastPoint(
            weather: .fixture(
                date: date,
                temperatureCelsius: temperatureCelsius,
                pressureHPa: pressureHPa,
                visibilityMeters: visibilityMeters,
                precipitationChance: precipitationChance,
                windSpeedMetersPerSecond: windSpeedMetersPerSecond
            ),
            biteScore: biteScore,
            tideHeightFeet: tideHeightFeet,
            tidePhase: tidePhase,
            solunarWindow: solunarWindow,
            pressureTendency: pressureTendency,
            moonPhase: moonPhase,
            sunrise: sunrise,
            sunset: sunset,
            tideRateFeetPerHour: tideRateFeetPerHour,
            nextTideTurn: nextTideTurn
        )
    }
}

private extension HourlyWeatherPoint {
    static func fixture(
        date: Date,
        temperatureCelsius: Double = 20,
        pressureHPa: Double? = 1_013,
        visibilityMeters: Double? = 16_000,
        precipitationChance: Double? = 0,
        windSpeedMetersPerSecond: Double = 3
    ) -> HourlyWeatherPoint {
        HourlyWeatherPoint(
            date: date,
            temperatureCelsius: temperatureCelsius,
            apparentTemperatureCelsius: temperatureCelsius,
            dewPointCelsius: nil,
            humidityFraction: 0.5,
            pressureHPa: pressureHPa,
            visibilityMeters: visibilityMeters,
            uvIndex: 3,
            cloudCoverFraction: 0.2,
            precipitationChance: precipitationChance,
            precipitationMM: 0,
            conditionText: "Clear",
            symbolName: "sun.max",
            wind: WindSnapshot(
                directionDegrees: 180,
                speedMetersPerSecond: windSpeedMetersPerSecond,
                gustMetersPerSecond: nil
            )
        )
    }
}

private extension WeatherSnapshot {
    static func fixture(
        now: Date,
        hourly: [HourlyWeatherPoint],
        astronomy: AstronomySnapshot = .empty,
        daily: [DailyWeatherPoint] = [],
        timeZoneIdentifier: String = "America/Chicago"
    ) -> WeatherSnapshot {
        WeatherSnapshot(
            coordinate: WeatherCoordinate(latitude: 30, longitude: -86),
            timeZoneIdentifier: timeZoneIdentifier,
            current: CurrentConditionsSnapshot(
                date: now,
                temperatureCelsius: 20,
                apparentTemperatureCelsius: 20,
                dewPointCelsius: nil,
                humidityFraction: 0.5,
                pressureHPa: 1_013,
                visibilityMeters: 16_000,
                uvIndex: 3,
                conditionText: "Clear",
                symbolName: "sun.max",
                wind: WindSnapshot(
                    directionDegrees: 180,
                    speedMetersPerSecond: 3,
                    gustMetersPerSecond: nil
                )
            ),
            hourly: hourly,
            daily: daily,
            alerts: [],
            astronomy: astronomy,
            provenance: WeatherProvenance(
                source: .weatherKit,
                fetchedAt: now,
                isFallback: false,
                attribution: "WeatherKit"
            )
        )
    }
}

private extension DailyWeatherPoint {
    static func fixture(
        date: Date,
        astronomy: AstronomySnapshot?
    ) -> DailyWeatherPoint {
        DailyWeatherPoint(
            date: date,
            lowCelsius: 15,
            highCelsius: 25,
            precipitationChance: 0,
            conditionText: "Clear",
            symbolName: "sun.max",
            windMetersPerSecond: 3,
            windPeakMetersPerSecond: nil,
            astronomy: astronomy
        )
    }
}
