import CoreLocation
import Foundation
import Testing
@testable import BiteCast

@Suite("Best bait context")
struct BestBaitContextTests {
    @Test("All species cannot create a best-bait context")
    func allSpeciesCannotClaimBestBait() {
        #expect(!BaitContextKey.canGenerate(for: .all))
        #expect(BestBaitContext(
            species: .all,
            coordinate: CLLocationCoordinate2D(latitude: 30, longitude: -86),
            weatherFetchedAt: Date(timeIntervalSince1970: 100),
            tideFingerprint: "tide-a",
            forecastPoint: Self.point(at: 3_600)
        ) == nil)
    }

    @Test("The active location is rounded into the context key")
    func activeLocationIsRounded() throws {
        let first = try #require(Self.context(
            latitude: 30.004,
            longitude: -86.004
        ))
        let nearby = try #require(Self.context(
            latitude: 30.003,
            longitude: -86.003
        ))
        let otherTile = try #require(Self.context(
            latitude: 30.016,
            longitude: -86.016
        ))

        #expect(first.key.locationKey == "30.00,-86.00")
        #expect(first.key == nearby.key)
        #expect(first.key != otherTile.key)
    }

    @Test("Coordinates outside the valid world bounds are rejected")
    func invalidCoordinatesAreRejected() {
        #expect(Self.context(latitude: 90, longitude: 180) != nil)
        #expect(Self.context(latitude: -90, longitude: -180) != nil)
        #expect(Self.context(latitude: 90.000_1) == nil)
        #expect(Self.context(latitude: -90.000_1) == nil)
        #expect(Self.context(longitude: 180.000_1) == nil)
        #expect(Self.context(longitude: -180.000_1) == nil)
    }

    @Test("Weather revision invalidates the recommendation key")
    func weatherRevisionInvalidates() throws {
        let first = try #require(Self.context(
            weatherFetchedAt: Date(timeIntervalSince1970: 100)
        ))
        let refreshed = try #require(Self.context(
            weatherFetchedAt: Date(timeIntervalSince1970: 101)
        ))

        #expect(first.key != refreshed.key)
    }

    @Test("Committed tide fingerprint invalidates the recommendation key")
    func tideFingerprintInvalidates() throws {
        let first = try #require(Self.context(tideFingerprint: "tide-a"))
        let refreshed = try #require(Self.context(tideFingerprint: "tide-b"))

        #expect(first.key != refreshed.key)
    }

    @Test("Selected forecast hour uses floor epoch buckets")
    func selectedForecastHourUsesFloorBuckets() throws {
        let beforeBoundary = try #require(Self.context(pointDate: 3_599))
        let afterBoundary = try #require(Self.context(pointDate: 3_601))
        let beforeEpoch = try #require(Self.context(pointDate: -1))

        #expect(beforeBoundary.key.forecastHourBucket == 0)
        #expect(afterBoundary.key.forecastHourBucket == 1)
        #expect(beforeBoundary.key != afterBoundary.key)
        #expect(beforeEpoch.key.forecastHourBucket == -1)
    }

    @Test("An out-of-range epoch hour is rejected without integer conversion")
    func outOfRangeEpochHourIsRejected() {
        let firstInvalidHour = Double(Int64.max)
        #expect(Self.context(
            pointDate: firstInvalidHour * 3_600
        ) == nil)
    }

    @Test("Tide fingerprint is stable for committed values and changes with data")
    func tideFingerprintUsesCommittedValues() {
        let event = TideEvent(
            time: Date(timeIntervalSince1970: 7_200),
            kind: .high,
            heightFeet: 2.4
        )
        let duplicateEvent = TideEvent(
            time: event.time,
            kind: event.kind,
            heightFeet: 2.5
        )
        let sample = TideSample(
            time: Date(timeIntervalSince1970: 7_200),
            heightFeet: 2.2
        )
        let duplicateSample = TideSample(
            time: sample.time,
            heightFeet: 2.1
        )
        let original = BaitContextKey.tideFingerprint(
            events: [event, duplicateEvent],
            samples: [sample, duplicateSample]
        )
        let permuted = BaitContextKey.tideFingerprint(
            events: [duplicateEvent, event],
            samples: [duplicateSample, sample]
        )
        let changed = BaitContextKey.tideFingerprint(
            events: [event, duplicateEvent],
            samples: [sample, TideSample(
                time: duplicateSample.time,
                heightFeet: 2.3
            )]
        )

        #expect(original == permuted)
        #expect(original != changed)
    }

    @Test("Prompt describes only the selected provider-neutral hour")
    func promptDescribesSelectedForecastPoint() throws {
        let point = Self.point(at: 7_200)
        let context = try #require(Self.context(forecastPoint: point))
        let repeated = try #require(Self.context(forecastPoint: point))

        #expect(context.promptSummary.contains("Selected forecast hour: 1970-01-01T02:00:00Z"))
        #expect(context.promptSummary.contains("Air temperature: 24.5 C"))
        #expect(context.promptSummary.contains("Pressure: 1012.0 hPa, Falling"))
        #expect(context.promptSummary.contains("Wind: 180 degrees at 8.9 mph, gusting 13.4 mph"))
        #expect(context.promptSummary.contains("Tide: 2.3 ft, Rising, rate 0.4 ft/hr"))
        #expect(context.promptSummary.contains("Deterministic bite score: 72/100"))
        #expect(context.promptSummary == repeated.promptSummary)
    }

    @Test("Prompt sanitizes invalid provider values")
    func promptSanitizesInvalidProviderValues() throws {
        let date = Date(timeIntervalSince1970: 7_200)
        let point = ForecastPoint(
            weather: HourlyWeatherPoint(
                date: date,
                temperatureCelsius: .nan,
                apparentTemperatureCelsius: .infinity,
                dewPointCelsius: -.infinity,
                humidityFraction: 4,
                pressureHPa: -.infinity,
                visibilityMeters: .nan,
                uvIndex: -1,
                cloudCoverFraction: 3,
                precipitationChance: 3,
                precipitationMM: -.infinity,
                conditionText: "Unknown",
                symbolName: "questionmark",
                wind: WindSnapshot(
                    directionDegrees: 720,
                    speedMetersPerSecond: -4,
                    gustMetersPerSecond: .infinity
                )
            ),
            biteScore: 101,
            tideHeightFeet: .nan,
            tidePhase: "Rising",
            solunarWindow: BiteWindow(
                period: .major,
                peak: Date(timeIntervalSince1970: .infinity),
                cause: "Invalid peak"
            ),
            pressureTendency: .rising,
            moonPhase: .full,
            tideRateFeetPerHour: .infinity,
            nextTideTurn: TideEvent(
                time: Date(timeIntervalSince1970: .infinity),
                kind: .high,
                heightFeet: .infinity
            )
        )
        let context = try #require(Self.context(forecastPoint: point))
        let summary = context.promptSummary
        let normalized = summary.lowercased()

        #expect(!normalized.contains("nan"))
        #expect(!normalized.contains("inf"))
        #expect(!summary.contains("300 percent"))
        #expect(!summary.contains("720 degrees"))
        #expect(!summary.contains("101/100"))
        #expect(summary.contains("Air temperature: unavailable"))
        #expect(summary.contains("Precipitation chance: unavailable"))
        #expect(summary.contains("Pressure: unavailable"))
        #expect(summary.contains("Wind: unavailable"))
        #expect(summary.contains("Tide: unavailable"))
        #expect(summary.contains("Deterministic bite score: unavailable"))
    }

    @MainActor
    @Test("Unavailable model publishes the deterministic profile starting point")
    func unavailableModelPublishesFallback() async throws {
        let context = try #require(Self.context())
        let workerCalls = BaitTestCounter()
        let engine = BaitEngine(
            modelAvailability: { .unavailable("Model disabled") },
            recommendationWorker: { _ in
                await workerCalls.increment()
                return Self.modelRecommendation(named: "Should not run")
            },
            clock: { Date(timeIntervalSince1970: 9_999) }
        )

        await engine.generateBestBait(for: .bass, context: context)

        let result = try #require(engine.result)
        let profile = BaitProfile.profile(for: .bass)
        #expect(result.recommendation.topBait == profile.baits.first)
        #expect(result.recommendation.technique == profile.techniques.first)
        #expect(result.sourceLabel == "General species guidance — not adjusted for today")
        #expect(result.generatedAt == nil)
        #expect(await workerCalls.value == 0)
    }

    @MainActor
    @Test("Model failure publishes the same deterministic profile guidance")
    func modelFailurePublishesFallback() async throws {
        let context = try #require(Self.context())
        let engine = BaitEngine(
            modelAvailability: { .available },
            recommendationWorker: { _ in throw BaitTestError.failed }
        )

        await engine.generateBestBait(for: .bass, context: context)

        let result = try #require(engine.result)
        let profile = BaitProfile.profile(for: .bass)
        #expect(result.recommendation.topBait == profile.baits.first)
        #expect(result.recommendation.technique == profile.techniques.first)
        #expect(result.sourceLabel == "General species guidance — not adjusted for today")
        #expect(result.generatedAt == nil)
    }

    @MainActor
    @Test("Only successful model output carries Apple provenance and generation time")
    func successfulModelCarriesAppleProvenance() async throws {
        let generatedAt = Date(timeIntervalSince1970: 9_999)
        let context = try #require(Self.context())
        let engine = BaitEngine(
            modelAvailability: { .available },
            recommendationWorker: { _ in
                Self.modelRecommendation(named: "Green pumpkin jig")
            },
            clock: { generatedAt }
        )

        await engine.generateBestBait(for: .bass, context: context)

        let result = try #require(engine.result)
        #expect(result.recommendation.topBait == "Green pumpkin jig")
        #expect(result.sourceLabel == "On-device Apple Intelligence")
        #expect(result.generatedAt == generatedAt)
    }

    @MainActor
    @Test("Primary generation leaves optional prose behind More advice")
    func primaryGenerationDoesNotStartOptionalAdvice() async throws {
        let context = try #require(Self.context())
        let adviceCalls = BaitTestCounter()
        let engine = BaitEngine(
            modelAvailability: { .available },
            recommendationWorker: { _ in
                Self.modelRecommendation(named: "Green pumpkin jig")
            },
            adviceWorker: { _, recommendation in
                await adviceCalls.increment()
                return "Use \(recommendation.topBait) around cover."
            }
        )

        await engine.generateBestBait(for: .bass, context: context)

        #expect(engine.report == nil)
        #expect(await adviceCalls.value == 0)

        await engine.generateMoreAdvice(for: context)

        #expect(engine.report == "Use Green pumpkin jig around cover.")
        #expect(await adviceCalls.value == 1)
    }

    private static func context(
        species: Species = .bass,
        latitude: Double = 30,
        longitude: Double = -86,
        weatherFetchedAt: Date = Date(timeIntervalSince1970: 100),
        tideFingerprint: String = "tide-a",
        pointDate: TimeInterval = 3_599,
        forecastPoint: ForecastPoint? = nil
    ) -> BestBaitContext? {
        BestBaitContext(
            species: species,
            coordinate: CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            ),
            weatherFetchedAt: weatherFetchedAt,
            tideFingerprint: tideFingerprint,
            forecastPoint: forecastPoint ?? point(at: pointDate)
        )
    }

    private static func point(at epoch: TimeInterval) -> ForecastPoint {
        let date = Date(timeIntervalSince1970: epoch)
        return ForecastPoint(
            weather: HourlyWeatherPoint(
                date: date,
                temperatureCelsius: 24.5,
                apparentTemperatureCelsius: 25.2,
                dewPointCelsius: 18,
                humidityFraction: 0.7,
                pressureHPa: 1_012,
                visibilityMeters: 16_000,
                uvIndex: 4,
                cloudCoverFraction: 0.25,
                precipitationChance: 0.2,
                precipitationMM: 0.5,
                conditionText: "Partly cloudy",
                symbolName: "cloud.sun",
                wind: WindSnapshot(
                    directionDegrees: 180,
                    speedMetersPerSecond: 4,
                    gustMetersPerSecond: 6
                )
            ),
            biteScore: 72,
            tideHeightFeet: 2.3,
            tidePhase: "Rising",
            solunarWindow: BiteWindow(
                period: .major,
                peak: date,
                cause: "Moon overhead"
            ),
            pressureTendency: .falling,
            moonPhase: .full,
            sunrise: date.addingTimeInterval(-3_600),
            sunset: date.addingTimeInterval(3_600),
            tideRateFeetPerHour: 0.4,
            nextTideTurn: TideEvent(
                time: date.addingTimeInterval(1_800),
                kind: .high,
                heightFeet: 2.6
            )
        )
    }

    static func modelRecommendation(named name: String) -> BaitRecommendation {
        BaitRecommendation(
            topBait: name,
            color: "Green pumpkin",
            technique: "Drag slowly",
            depth: "4–8 ft",
            confidence: 92,
            whyReason: "The selected forecast hour has falling pressure."
        )
    }
}

private enum BaitTestError: Error {
    case failed
}

private actor BaitTestCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
