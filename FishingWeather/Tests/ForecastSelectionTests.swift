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

    @Test func windChartIncludesSustainedAndGustSeries() {
        let point = ForecastPoint.fixture(
            windSpeedMetersPerSecond: 4,
            windGustMetersPerSecond: 8
        )

        let values = ForecastMetric.wind.chartValues(
            for: point,
            locale: Locale(identifier: "en_US")
        )

        #expect(values.map(\.series) == [.primary, .gust])
        #expect(values[1].value > values[0].value)
    }

    @Test func unavailableMetricKeepsPinnedDetailContract() {
        let point = ForecastPoint.fixture(pressureHPa: nil)

        let content = ForecastChartContent.resolve(
            points: [point],
            selectedDate: point.date,
            metric: .pressure,
            locale: Locale(identifier: "en_US")
        )

        #expect(content.metricValues.isEmpty)
        #expect(content.selectedPoint == point)
        #expect(content.showsPinnedDetail)
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

    @Test func builderKeepsPriorDayWindowActiveAcrossMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let previousDay = try #require(calendar.date(
            from: DateComponents(year: 2030, month: 1, day: 1, hour: 12)
        ))
        let peak = try #require(calendar.date(
            from: DateComponents(year: 2030, month: 1, day: 1, hour: 23, minute: 45)
        ))
        let selectedHour = try #require(calendar.date(
            from: DateComponents(year: 2030, month: 1, day: 2, hour: 0)
        ))
        let snapshot = WeatherSnapshot.fixture(
            now: selectedHour,
            hourly: [.fixture(date: selectedHour)],
            astronomy: .empty,
            daily: [
                .fixture(
                    date: previousDay,
                    astronomy: AstronomySnapshot(
                        sunrise: nil,
                        sunset: nil,
                        moonrise: peak,
                        moonset: nil,
                        moonTransit: nil,
                        moonPhaseFraction: nil
                    )
                ),
                .fixture(date: selectedHour, astronomy: .empty),
            ],
            timeZoneIdentifier: "UTC"
        )

        let point = try #require(ForecastSeriesBuilder.build(
            weather: snapshot,
            tideSamples: [],
            species: .bass,
            now: selectedHour
        ).first)

        #expect(point.solunarWindow?.peak == peak)
        #expect(point.solunarWindow?.cause == "Moonrise")
    }

    @Test func nextDayWindowChangesLateDayScore() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let selectedHour = try #require(calendar.date(
            from: DateComponents(year: 2030, month: 1, day: 1, hour: 23, minute: 15)
        ))
        let nextDay = try #require(calendar.date(
            from: DateComponents(year: 2030, month: 1, day: 2, hour: 12)
        ))
        let nextPeak = try #require(calendar.date(
            from: DateComponents(year: 2030, month: 1, day: 2, hour: 0, minute: 15)
        ))
        let nextAstronomy = AstronomySnapshot(
            sunrise: nil,
            sunset: nil,
            moonrise: nextPeak,
            moonset: nil,
            moonTransit: nil,
            moonPhaseFraction: nil
        )
        let withUpcoming = WeatherSnapshot.fixture(
            now: selectedHour,
            hourly: [.fixture(date: selectedHour)],
            astronomy: .empty,
            daily: [
                .fixture(date: selectedHour, astronomy: .empty),
                .fixture(date: nextDay, astronomy: nextAstronomy),
            ],
            timeZoneIdentifier: "UTC"
        )
        let withoutUpcoming = WeatherSnapshot.fixture(
            now: selectedHour,
            hourly: [.fixture(date: selectedHour)],
            astronomy: .empty,
            daily: [
                .fixture(date: selectedHour, astronomy: .empty),
                .fixture(date: nextDay, astronomy: .empty),
            ],
            timeZoneIdentifier: "UTC"
        )

        let withPoint = try #require(ForecastSeriesBuilder.build(
            weather: withUpcoming,
            tideSamples: [],
            species: .bass,
            now: selectedHour
        ).first)
        let withoutPoint = try #require(ForecastSeriesBuilder.build(
            weather: withoutUpcoming,
            tideSamples: [],
            species: .bass,
            now: selectedHour
        ).first)

        #expect(withPoint.biteScore != withoutPoint.biteScore)
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

    @Test func unsupportedFactorsAreOmitted() {
        let point = ForecastPoint.fixture(
            pressureHPa: nil,
            visibilityMeters: nil
        )

        let rows = ForecastFactorRow.rows(for: [point])

        #expect(!rows.map(\.id).contains(.pressure))
        #expect(!rows.map(\.id).contains(.visibility))
    }

    @Test func zeroValuesRemainAvailableAndAreNotRenderedAsMissing() throws {
        let point = ForecastPoint.fixture(
            precipitationChance: 0,
            precipitationMM: 0,
            windSpeedMetersPerSecond: 0,
            windGustMetersPerSecond: 0,
            biteScore: 0,
            tideHeightFeet: 0,
            tideRateFeetPerHour: 0
        )
        let rows = ForecastFactorRow.rows(for: [point])
        let ids = Set(rows.map(\.id))

        #expect(ids.isSuperset(of: [
            .biteScore,
            .precipitationChance,
            .precipitationAmount,
            .windSpeed,
            .windGust,
            .tideHeight,
            .tideMovement,
        ]))
        let precipitation = try #require(
            rows.first { $0.id == .precipitationChance }
        )
        #expect(precipitation.formattedValue(
            for: point,
            locale: Locale(identifier: "en_US"),
            timeZone: .gmt
        ) == "0%")
        let tide = try #require(rows.first { $0.id == .tideHeight })
        #expect(tide.formattedValue(
            for: point,
            locale: Locale(identifier: "en_US"),
            timeZone: .gmt
        ) != nil)
    }

    @Test func biteBandsUseOneExactFiveThresholdContract() {
        #expect(BiteScoreBand.band(for: 100) == .excellent)
        #expect(BiteScoreBand.band(for: 85) == .excellent)
        #expect(BiteScoreBand.band(for: 84) == .strong)
        #expect(BiteScoreBand.band(for: 70) == .strong)
        #expect(BiteScoreBand.band(for: 69) == .fair)
        #expect(BiteScoreBand.band(for: 50) == .fair)
        #expect(BiteScoreBand.band(for: 49) == .tough)
        #expect(BiteScoreBand.band(for: 30) == .tough)
        #expect(BiteScoreBand.band(for: 29) == .poor)
        #expect(BiteScoreBand.band(for: 0) == .poor)
        #expect(BiteScoreBand.band(for: -1) == nil)
        #expect(BiteScoreBand.band(for: 101) == nil)
        #expect(BiteScoreBand.allCases.map(\.rangeLabel) == [
            "85–100",
            "70–84",
            "50–69",
            "30–49",
            "0–29",
        ])
    }

    @Test func timelineBiteDetailUsesSharedBoundariesAndRejectsInvalidScores() {
        let cases: [(score: Int?, expected: String)] = [
            (85, "85 / 100 · Excellent"),
            (70, "70 / 100 · Strong"),
            (50, "50 / 100 · Fair"),
            (30, "30 / 100 · Tough"),
            (0, "0 / 100 · Poor"),
            (-1, "Unavailable"),
            (101, "Unavailable"),
            (nil, "Unavailable"),
        ]

        for item in cases {
            #expect(
                ForecastTimelineBiteDetail.formatted(score: item.score)
                    == item.expected
            )
        }
    }

    @Test func scoreSummaryAndForecastRowsShareTheDomainBandContract() throws {
        let score = FishingScore(factors: [
            ScoreFactor(
                kind: .solunar,
                label: "Solunar",
                weight: 1,
                raw: 0.69,
                detail: "Fixture"
            ),
        ])
        let point = ForecastPoint.fixture(biteScore: score.overall)
        let row = try #require(
            ForecastFactorRow.rows(for: [point]).first { $0.id == .biteScore }
        )

        #expect(score.band == .fair)
        #expect(score.summary == BiteScoreBand.fair.title)
        #expect(Ink.scoreBand(for: score.overall) == score.band)
        #expect(row.formattedValue(
            for: point,
            locale: Locale(identifier: "en_US"),
            timeZone: .gmt
        ) == "69 · Fair")
        #expect(
            ForecastTimelineBiteDetail.formatted(score: score.overall)
                == "69 / 100 · Fair"
        )
    }

    @Test func selectedDetailRejectsTheSameInvalidValuesAsMatrixRows() {
        let invalid = ForecastPoint.fixture(
            temperatureCelsius: .nan,
            biteScore: 101
        )
        let content = ForecastSelectedDetailContent(
            point: invalid,
            locale: Locale(identifier: "en_US"),
            timeZone: .gmt
        )

        #expect(content.temperature == nil)
        #expect(content.biteScore == nil)
        #expect(content.biteBand == nil)
    }

    @Test func nonFiniteAndOutOfDomainFactorsAreOmitted() {
        let point = ForecastPoint.fixture(
            pressureHPa: .nan,
            visibilityMeters: -1,
            precipitationChance: 1.1,
            precipitationMM: -0.1,
            humidityFraction: -0.1,
            uvIndex: -1,
            cloudCoverFraction: 1.1,
            windDirectionDegrees: 361,
            windSpeedMetersPerSecond: -1,
            windGustMetersPerSecond: -.infinity,
            biteScore: 101
        )

        let ids = Set(ForecastFactorRow.rows(for: [point]).map(\.id))

        #expect(!ids.contains(.pressure))
        #expect(!ids.contains(.visibility))
        #expect(!ids.contains(.precipitationChance))
        #expect(!ids.contains(.precipitationAmount))
        #expect(!ids.contains(.humidity))
        #expect(!ids.contains(.uvIndex))
        #expect(!ids.contains(.cloudCover))
        #expect(!ids.contains(.windDirection))
        #expect(!ids.contains(.windSpeed))
        #expect(!ids.contains(.windGust))
        #expect(!ids.contains(.biteScore))
    }

    @Test func matrixValuesUseLocaleUnitsAndTargetTimeZone() throws {
        let sunrise = Date(timeIntervalSince1970: 1_800_000_000)
        let point = ForecastPoint.fixture(
            temperatureCelsius: 20,
            visibilityMeters: 1_609.344,
            sunrise: sunrise
        )
        let rows = ForecastFactorRow.rows(for: [point])
        let temperature = try #require(rows.first { $0.id == .temperature })
        let visibility = try #require(rows.first { $0.id == .visibility })
        let sunriseRow = try #require(rows.first { $0.id == .sunrise })
        let chicago = try #require(TimeZone(identifier: "America/Chicago"))

        let usTemperature = try #require(temperature.formattedValue(
            for: point,
            locale: Locale(identifier: "en_US"),
            timeZone: .gmt
        ))
        let metricTemperature = try #require(temperature.formattedValue(
            for: point,
            locale: Locale(identifier: "en_GB"),
            timeZone: .gmt
        ))
        let usVisibility = try #require(visibility.formattedValue(
            for: point,
            locale: Locale(identifier: "en_US"),
            timeZone: .gmt
        ))
        let metricVisibility = try #require(visibility.formattedValue(
            for: point,
            locale: Locale(identifier: "en_GB"),
            timeZone: .gmt
        ))
        let chicagoSunrise = try #require(sunriseRow.formattedValue(
            for: point,
            locale: Locale(identifier: "en_US"),
            timeZone: chicago
        ))
        let utcSunrise = try #require(sunriseRow.formattedValue(
            for: point,
            locale: Locale(identifier: "en_US"),
            timeZone: .gmt
        ))

        #expect(usTemperature.contains("68"))
        #expect(metricTemperature.contains("20"))
        #expect(usVisibility.contains("1"))
        #expect(usVisibility.localizedCaseInsensitiveContains("mi"))
        #expect(metricVisibility.contains("1.6"))
        #expect(metricVisibility.localizedCaseInsensitiveContains("km"))
        #expect(chicagoSunrise != utcSunrise)
    }

    @Test func preferencesNormalizeStableIDsAndRoundTrip() {
        let preferences = ForecastFactorPreferences(
            storedOrder: "wind,unknown,wind,fishing",
            storedCollapsed: "waterAndSky,unknown,waterAndSky"
        )

        #expect(preferences.orderedGroups == [
            .wind,
            .fishing,
            .weather,
            .waterAndSky,
        ])
        #expect(preferences.collapsedGroups == [.waterAndSky])

        let restored = ForecastFactorPreferences(
            storedOrder: preferences.storedOrder,
            storedCollapsed: preferences.storedCollapsed
        )
        #expect(restored == preferences)
    }

    @Test func preferencesMoveGroupsWithoutDroppingAny() {
        var preferences = ForecastFactorPreferences()

        #expect(!preferences.canMove(.fishing, direction: .earlier))
        #expect(preferences.canMove(.fishing, direction: .later))
        preferences.move(.waterAndSky, direction: .earlier)
        preferences.toggleCollapsed(.weather)

        #expect(preferences.orderedGroups == [
            .fishing,
            .weather,
            .waterAndSky,
            .wind,
        ])
        #expect(preferences.collapsedGroups == [.weather])
        #expect(Set(preferences.orderedGroups) == Set(ForecastFactorGroup.allCases))
    }

    @Test func preferencesReorderVisibleGroupsWithoutMovingHiddenSlots() {
        var preferences = ForecastFactorPreferences(
            storedOrder: "fishing,weather,wind,waterAndSky"
        )
        let visible: Set<ForecastFactorGroup> = [.fishing, .wind, .waterAndSky]

        #expect(!preferences.canMove(
            .fishing,
            direction: .earlier,
            among: visible
        ))
        #expect(preferences.canMove(
            .fishing,
            direction: .later,
            among: visible
        ))
        preferences.move(.fishing, direction: .later, among: visible)

        #expect(preferences.orderedGroups == [
            .wind,
            .weather,
            .fishing,
            .waterAndSky,
        ])
        #expect(preferences.orderedGroups[1] == .weather)
    }

#if DEBUG
    @Test @MainActor func proForecastPreviewUsesGMTMidnightAndIsolatedPreferences() {
        let start = ProForecastPreviewFixture.start
        let midnight = ProForecastPreviewFixture.dayStart(for: start)
        let points = ProForecastPreviewFixture.points
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ProForecastPreviewFixture.timeZone

        #expect(ProForecastPreviewFixture.locale.identifier == "en_US_POSIX")
        #expect(ProForecastPreviewFixture.timeZone == .gmt)
        #expect(midnight <= start)
        #expect(start.timeIntervalSince(midnight) < 86_400)
        #expect(
            ProForecastPreviewFixture.preferenceSuiteName
                == "app.choatelabs.bitecast.debug.proForecast.v1"
        )
        #expect(points.count == 48)
        #expect(points.allSatisfy { point in
            guard let nextTurn = point.nextTideTurn else { return false }
            return nextTurn.time > point.date
        })
        #expect(points.allSatisfy { point in
            guard let nextTurn = point.nextTideTurn else { return false }
            return [8, 20].contains(calendar.component(.hour, from: nextTurn.time))
        })

        let key = "proForecast.fixturePersistenceProbe"
        ProForecastPreviewFixture.preferenceStore.set("kept", forKey: key)
        #expect(
            ProForecastPreviewFixture.preferenceStore.string(forKey: key)
                == "kept"
        )
        ProForecastPreviewFixture.preferenceStore.removeObject(forKey: key)
    }
#endif

    @Test func weekRequiresSevenContiguousDaysOfHourlyPoints() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let twoDays = (0..<48).map {
            ForecastPoint.fixture(
                date: start.addingTimeInterval(Double($0) * 3_600)
            )
        }
        let fullWeek = (0..<(7 * 24)).map {
            ForecastPoint.fixture(
                date: start.addingTimeInterval(Double($0) * 3_600)
            )
        }
        let sparseWeek = stride(from: 0, to: 7 * 24, by: 2).map {
            ForecastPoint.fixture(
                date: start.addingTimeInterval(Double($0) * 3_600)
            )
        }
        let ninetyMinuteSamples = (0..<(7 * 24)).map {
            ForecastPoint.fixture(
                date: start.addingTimeInterval(Double($0) * 5_400)
            )
        }

        #expect(ProForecastHorizon.available(for: twoDays) == [.day])
        #expect(ProForecastHorizon.available(for: fullWeek) == [.day, .week])
        #expect(ProForecastHorizon.available(for: sparseWeek) == [.day])
        #expect(ProForecastHorizon.available(for: ninetyMinuteSamples) == [.day])
        #expect(ProForecastHorizon.allCases == [.day, .week])
    }
}

private extension ForecastPoint {
    static func fixture(
        date: Date = Date(timeIntervalSince1970: 1_800_000_000),
        temperatureCelsius: Double = 20,
        pressureHPa: Double? = 1_013,
        visibilityMeters: Double? = 16_000,
        precipitationChance: Double? = 0,
        precipitationMM: Double? = 0,
        humidityFraction: Double? = 0.5,
        uvIndex: Int? = 3,
        cloudCoverFraction: Double? = 0.2,
        windDirectionDegrees: Double = 180,
        windSpeedMetersPerSecond: Double = 3,
        windGustMetersPerSecond: Double? = nil,
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
                precipitationMM: precipitationMM,
                humidityFraction: humidityFraction,
                uvIndex: uvIndex,
                cloudCoverFraction: cloudCoverFraction,
                windDirectionDegrees: windDirectionDegrees,
                windSpeedMetersPerSecond: windSpeedMetersPerSecond,
                windGustMetersPerSecond: windGustMetersPerSecond
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
        precipitationMM: Double? = 0,
        humidityFraction: Double? = 0.5,
        uvIndex: Int? = 3,
        cloudCoverFraction: Double? = 0.2,
        windDirectionDegrees: Double = 180,
        windSpeedMetersPerSecond: Double = 3,
        windGustMetersPerSecond: Double? = nil
    ) -> HourlyWeatherPoint {
        HourlyWeatherPoint(
            date: date,
            temperatureCelsius: temperatureCelsius,
            apparentTemperatureCelsius: temperatureCelsius,
            dewPointCelsius: nil,
            humidityFraction: humidityFraction,
            pressureHPa: pressureHPa,
            visibilityMeters: visibilityMeters,
            uvIndex: uvIndex,
            cloudCoverFraction: cloudCoverFraction,
            precipitationChance: precipitationChance,
            precipitationMM: precipitationMM,
            conditionText: "Clear",
            symbolName: "sun.max",
            wind: WindSnapshot(
                directionDegrees: windDirectionDegrees,
                speedMetersPerSecond: windSpeedMetersPerSecond,
                gustMetersPerSecond: windGustMetersPerSecond
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
