import CoreLocation
import Foundation
import Testing
@testable import BiteCast

@Suite("Async state identity")
struct AsyncStateIdentityTests {
    @MainActor
    @Test("Newer neutral weather snapshot wins")
    func newerNeutralSnapshotWins() async {
        let oldStarted = AsyncStartSignal()
        let store = WeatherStore(worker: { location, now in
            if location.coordinate.latitude == 30 {
                await oldStarted.markStarted()
                try await Task.sleep(for: .milliseconds(80))
            }
            return Self.snapshot(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                fetchedAt: now
            )
        })

        let old = Task {
            await store.load(for: CLLocation(latitude: 30, longitude: -86))
        }
        await oldStarted.wait()
        await store.load(for: CLLocation(latitude: 31, longitude: -87))
        await old.value

        #expect(store.snapshot?.coordinate.latitude == 31)
        #expect(store.provenance?.source == .nws)
        #expect(store.hasData(for: CLLocation(latitude: 31, longitude: -87)))
        #expect(!store.hasData(for: CLLocation(latitude: 30, longitude: -86)))
    }

    @MainActor
    @Test("Stale weather failure cannot overwrite a newer success")
    func staleWeatherFailureDoesNotCommit() async {
        let oldStarted = AsyncStartSignal()
        let store = WeatherStore(worker: { location, now in
            if location.coordinate.latitude == 30 {
                await oldStarted.markStarted()
                try await Task.sleep(for: .milliseconds(80))
                throw WeatherProviderError.authentication
            }
            return Self.snapshot(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                fetchedAt: now
            )
        })

        let old = Task {
            await store.load(for: CLLocation(latitude: 30, longitude: -86))
        }
        await oldStarted.wait()
        await store.load(for: CLLocation(latitude: 31, longitude: -87))
        await old.value

        #expect(store.snapshot?.coordinate.latitude == 31)
        #expect(store.errorMessage == nil)
        #expect(!store.isLoading)
    }

    @MainActor
    @Test("Canceled weather request cannot commit a snapshot or error")
    func canceledWeatherRequestDoesNotCommit() async {
        let started = AsyncStartSignal()
        let store = WeatherStore(worker: { location, now in
            await started.markStarted()
            // Simulate a provider that observes cancellation but still returns
            // a late value; the store owns the final commit guard.
            try? await Task.sleep(for: .seconds(10))
            return Self.snapshot(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                fetchedAt: now
            )
        })

        let task = Task {
            await store.load(for: CLLocation(latitude: 30, longitude: -86))
        }
        await started.wait()
        task.cancel()
        await task.value

        #expect(store.snapshot == nil)
        #expect(store.loadedKey == nil)
        #expect(store.errorMessage == nil)
        #expect(!store.isLoading)
    }

    @MainActor
    @Test("Typed authentication error has a stable user-facing message")
    func weatherAuthenticationErrorIsUserFacing() async {
        let store = WeatherStore(worker: { _, _ in
            throw WeatherProviderError.allProvidersFailed([
                WeatherProviderFailure(
                    provider: "NestedChain",
                    error: .allProvidersFailed([
                        WeatherProviderFailure(
                            provider: "TransientProvider",
                            error: .network("offline")
                        ),
                        WeatherProviderFailure(
                            provider: "WeatherKitProvider",
                            error: .authentication
                        ),
                    ])
                ),
                WeatherProviderFailure(
                    provider: "NWSWeatherProvider",
                    error: .serviceUnavailable
                ),
            ])
        })

        await store.load(for: CLLocation(latitude: 30, longitude: -86))

        #expect(store.snapshot == nil)
        #expect(store.errorMessage == "Weather authorization failed. Check the app's WeatherKit entitlement.")
        #expect(!store.isLoading)
    }

    @MainActor
    @Test("Fresh matching weather uses the fifteen-minute TTL unless forced")
    func matchingFreshWeatherUsesTTL() async {
        let calls = AsyncCounter()
        let store = WeatherStore(worker: { location, now in
            await calls.increment()
            return Self.snapshot(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                fetchedAt: now
            )
        })
        let location = CLLocation(latitude: 30, longitude: -86)

        await store.load(for: location)
        await store.load(for: location)
        #expect(await calls.value == 1)

        await store.load(for: location, force: true)
        #expect(await calls.value == 2)
    }

    @MainActor
    @Test("Matching weather expires after the fifteen-minute TTL")
    func matchingWeatherExpiresAfterTTL() async {
        let calls = AsyncCounter()
        var currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = WeatherStore(
            worker: { location, fetchedAt in
                await calls.increment()
                return Self.snapshot(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    fetchedAt: fetchedAt
                )
            },
            now: { currentDate }
        )
        let location = CLLocation(latitude: 30, longitude: -86)

        await store.load(for: location)
        currentDate = currentDate.addingTimeInterval(15 * 60 + 1)
        await store.load(for: location)

        #expect(await calls.value == 2)
    }

    @MainActor
    @Test("A nearby cached coordinate is owned by the requested store key")
    func nearbyCachedCoordinateUsesRequestedIdentity() async {
        let persistedLocation = CLLocation(latitude: 30.2938, longitude: -86.0049)
        let requestedLocation = CLLocation(latitude: 30.31, longitude: -86.01)
        let store = WeatherStore(worker: { _, now in
            Self.snapshot(
                latitude: persistedLocation.coordinate.latitude,
                longitude: persistedLocation.coordinate.longitude,
                fetchedAt: now,
                source: .cache
            )
        })

        await store.load(for: requestedLocation)

        #expect(store.hasData(for: requestedLocation))
        #expect(!store.hasData(for: persistedLocation))
        #expect(store.snapshot?.coordinate.latitude == persistedLocation.coordinate.latitude)
    }

    @MainActor
    @Test("Only live weather successes are offered to the cache writer")
    func storeDoesNotResaveCachedFallback() async {
        let writes = SnapshotRecorder()
        let source = WeatherSourceSequence([.nws, .cache])
        let store = WeatherStore(
            worker: { location, now in
                let next = await source.next()
                return Self.snapshot(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    fetchedAt: now,
                    source: next
                )
            },
            cacheWriter: { snapshot in
                await writes.append(snapshot)
            }
        )
        let location = CLLocation(latitude: 30, longitude: -86)

        await store.load(for: location)
        await store.load(for: location, force: true)

        #expect(await writes.sources == [.nws])
    }

    @Test("Trip requests distinguish display names at the same coordinate")
    func tripRequestsIncludeLocationName() {
        let location = CLLocation(latitude: 27.7634, longitude: -82.6403)

        let old = TripForecastLoader.requestKey(
            location: location,
            species: .bass,
            locationName: "Current spot"
        )
        let updated = TripForecastLoader.requestKey(
            location: location,
            species: .bass,
            locationName: "St. Petersburg"
        )

        #expect(old != updated)
    }

    @MainActor
    @Test("Trip outlook reloads when same-location weather is refreshed")
    func tripOutlookIncludesSnapshotRevision() async {
        let calls = AsyncCounter()
        let loader = TripForecastLoader(worker: { _, _, locationName in
            await calls.increment()
            return WeekOutlook(
                locationName: locationName,
                generatedAt: .now,
                windows: []
            )
        })
        let location = CLLocation(latitude: 27.7634, longitude: -82.6403)
        let first = Self.snapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let refreshed = Self.snapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_900)
        )

        _ = await loader.load(
            for: location,
            species: .bass,
            locationName: "St. Petersburg",
            snapshot: nil
        )
        _ = await loader.load(
            for: location,
            species: .bass,
            locationName: "St. Petersburg",
            snapshot: first
        )
        _ = await loader.load(
            for: location,
            species: .bass,
            locationName: "St. Petersburg",
            snapshot: refreshed
        )

        #expect(await calls.value == 3)
    }

    @Test("Catch tide phase is omitted when events belong to another location")
    func tidePhaseRequiresMatchingData() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let events = [
            TideEvent(time: now.addingTimeInterval(-7_200), kind: .low, heightFeet: 0.2),
            TideEvent(time: now.addingTimeInterval(7_200), kind: .high, heightFeet: 2.4),
        ]

        #expect(LogCatchView.tidePhase(events: events, hasMatchingData: false, now: now) == nil)
        #expect(LogCatchView.tidePhase(events: events, hasMatchingData: true, now: now) == "Rising")
    }

    @Test("Tide request keys distinguish rounded coordinates")
    func tideKeysIncludeLocation() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = CLLocation(latitude: 27.76, longitude: -82.64)
        let b = CLLocation(latitude: 28.76, longitude: -83.64)

        #expect(TideService.dataKey(a, date: date) != TideService.dataKey(b, date: date))
    }

    @Test("An answer generation is stale after reset advances the generation")
    func staleAnswerGenerationIsRejected() {
        #expect(BaitEngine.isCurrentGeneration(3, current: 3))
        #expect(!BaitEngine.isCurrentGeneration(3, current: 4))
    }

    @MainActor
    @Test("Canceling a trip load cannot commit an outlook")
    func canceledTripLoadDoesNotCommit() async {
        let loader = TripForecastLoader(worker: { _, _, locationName in
            try? await Task.sleep(for: .seconds(10))
            return WeekOutlook(locationName: locationName, generatedAt: .now, windows: [])
        })
        let location = CLLocation(latitude: 27.76, longitude: -82.64)

        let task = Task {
            await loader.load(for: location, species: .bass, locationName: "Canceled")
        }
        await Task.yield()
        task.cancel()
        let result = await task.value

        #expect(result == nil)
        #expect(loader.outlook == nil)
        #expect(!loader.isLoading)
    }

    @MainActor
    @Test("Only one same-generation AI question runs at a time")
    func concurrentQuestionsAreRejected() async {
        let started = AsyncStartSignal()
        let engine = BaitEngine(answerWorker: { question in
            await started.markStarted()
            try await Task.sleep(for: .milliseconds(100))
            return "Answer to \(question)"
        })

        let first = Task { await engine.ask("first") }
        await started.wait()
        await engine.ask("second")
        await first.value

        #expect(engine.answers.count == 1)
        #expect(engine.answers.first?.question == "first")
        #expect(!engine.isAnswering)
    }

    @MainActor
    @Test("Reset prevents an in-flight AI answer from returning")
    func resetDropsInflightAnswer() async {
        let started = AsyncStartSignal()
        let engine = BaitEngine(answerWorker: { _ in
            await started.markStarted()
            try await Task.sleep(for: .milliseconds(100))
            return "Stale answer"
        })

        let task = Task { await engine.ask("old question") }
        await started.wait()
        engine.reset()
        await task.value

        #expect(engine.answers.isEmpty)
        #expect(!engine.isAnswering)
    }

    private nonisolated static func snapshot(
        latitude: Double,
        longitude: Double,
        fetchedAt: Date,
        source: WeatherSource = .nws
    ) -> WeatherSnapshot {
        let wind = WindSnapshot(
            directionDegrees: 180,
            speedMetersPerSecond: 4,
            gustMetersPerSecond: nil
        )
        return WeatherSnapshot(
            coordinate: WeatherCoordinate(latitude: latitude, longitude: longitude),
            timeZoneIdentifier: "America/Chicago",
            current: CurrentConditionsSnapshot(
                date: fetchedAt,
                temperatureCelsius: 24.6,
                apparentTemperatureCelsius: 25.2,
                dewPointCelsius: 19,
                humidityFraction: 0.7,
                pressureHPa: 1_015,
                visibilityMeters: 16_000,
                uvIndex: 4,
                conditionText: "Clear",
                symbolName: "sun.max",
                wind: wind
            ),
            hourly: [],
            daily: [],
            alerts: [],
            astronomy: .empty,
            provenance: WeatherProvenance(
                source: source,
                fetchedAt: fetchedAt,
                isFallback: source == .cache,
                attribution: nil
            )
        )
    }
}

private actor AsyncStartSignal {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        started = true
        let currentWaiters = waiters
        waiters.removeAll()
        currentWaiters.forEach { $0.resume() }
    }

    func wait() async {
        if started { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor AsyncCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private actor SnapshotRecorder {
    private var snapshots: [WeatherSnapshot] = []

    var sources: [WeatherSource] {
        snapshots.map(\.provenance.source)
    }

    func append(_ snapshot: WeatherSnapshot) {
        snapshots.append(snapshot)
    }
}

private actor WeatherSourceSequence {
    private var values: [WeatherSource]

    init(_ values: [WeatherSource]) {
        self.values = values
    }

    func next() -> WeatherSource {
        values.removeFirst()
    }
}
