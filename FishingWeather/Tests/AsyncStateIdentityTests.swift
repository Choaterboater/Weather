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
        #expect(store.lastProviderError == nil)
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
        #expect(store.lastProviderError == nil)
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
        #expect(store.lastProviderError == .allProvidersFailed([
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
        ]))
        #expect(store.errorMessage == "Weather authorization failed. Check the app's WeatherKit entitlement.")
        #expect(!store.isLoading)
    }

    @MainActor
    @Test("A failed forced refresh keeps matching live and cached content")
    func failedForcedRefreshKeepsMatchingContent() async {
        let location = CLLocation(latitude: 30, longitude: -86)

        for source in [WeatherSource.nws, .cache] {
            let attempts = AsyncCounter()
            let store = WeatherStore(worker: { location, now in
                if await attempts.next() == 1 {
                    return Self.snapshot(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        fetchedAt: now,
                        source: source
                    )
                }
                throw WeatherProviderError.rateLimited(retryAfter: 120)
            })

            await store.load(for: location)
            let original = store.snapshot
            await store.load(for: location, force: true)

            #expect(store.snapshot == original)
            #expect(store.hasData(for: location))
            #expect(store.lastProviderError == .rateLimited(retryAfter: 120))
            #expect(store.errorMessage == "The weather service is busy. Try again in 120 seconds.")
            #expect(!store.isLoading)
        }
    }

    @MainActor
    @Test("A fresh TTL hit clears a retained refresh error without refetching")
    func freshTTLHitClearsRetainedRefreshError() async {
        let attempts = AsyncCounter()
        let location = CLLocation(latitude: 30, longitude: -86)
        let store = WeatherStore(worker: { location, now in
            if await attempts.next() == 1 {
                return Self.snapshot(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    fetchedAt: now
                )
            }
            throw WeatherProviderError.network("offline")
        })

        await store.load(for: location)
        await store.load(for: location, force: true)
        #expect(store.lastProviderError == .network("offline"))

        await store.load(for: location)

        #expect(await attempts.value == 2)
        #expect(store.hasData(for: location))
        #expect(store.lastProviderError == nil)
        #expect(store.errorMessage == nil)
    }

    @MainActor
    @Test("A successful refresh clears an earlier typed provider error")
    func successfulRefreshClearsTypedError() async {
        let attempts = AsyncCounter()
        let location = CLLocation(latitude: 30, longitude: -86)
        let store = WeatherStore(worker: { location, now in
            switch await attempts.next() {
            case 1:
                return Self.snapshot(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    fetchedAt: now,
                    source: .nws
                )
            case 2:
                throw WeatherProviderError.serviceUnavailable
            default:
                return Self.snapshot(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    fetchedAt: now,
                    source: .weatherKit
                )
            }
        })

        await store.load(for: location)
        await store.load(for: location, force: true)
        #expect(store.lastProviderError == .serviceUnavailable)

        await store.load(for: location, force: true)

        #expect(store.provenance?.source == .weatherKit)
        #expect(store.lastProviderError == nil)
        #expect(store.errorMessage == nil)
    }

    @MainActor
    @Test("A different-location failure clears old content and retains its type")
    func differentLocationFailureClearsOldContent() async {
        let oldLocation = CLLocation(latitude: 30, longitude: -86)
        let newLocation = CLLocation(latitude: 31, longitude: -87)
        let store = WeatherStore(worker: { location, now in
            guard location.coordinate.latitude == 30 else {
                throw WeatherProviderError.unsupportedRegion
            }
            return Self.snapshot(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                fetchedAt: now
            )
        })

        await store.load(for: oldLocation)
        await store.load(for: newLocation)

        #expect(store.snapshot == nil)
        #expect(store.loadedKey == nil)
        #expect(!store.hasData(for: oldLocation))
        #expect(!store.hasData(for: newLocation))
        #expect(store.lastProviderError == .unsupportedRegion)
        #expect(store.errorMessage == "Weather is not available for this location.")
    }

    @MainActor
    @Test("An untyped worker failure is normalized into a typed network error")
    func untypedFailureIsNormalized() async {
        let store = WeatherStore(worker: { _, _ in
            throw AsyncWeatherError.offline
        })

        await store.load(for: CLLocation(latitude: 30, longitude: -86))

        #expect(store.lastProviderError == .network("offline"))
        #expect(store.errorMessage == "offline")
    }

    @Test("Every provider failure has a distinct presentation category")
    func providerFailurePresentationCategoriesAreDistinct() {
        #expect(WeatherProviderError.authentication.presentationKind == .authentication)
        #expect(WeatherProviderError.network("offline").presentationKind == .network(message: "offline"))
        #expect(WeatherProviderError.rateLimited(retryAfter: 30).presentationKind == .rateLimited(retryAfter: 30))
        #expect(WeatherProviderError.serviceUnavailable.presentationKind == .serviceUnavailable)
        #expect(WeatherProviderError.unsupportedRegion.presentationKind == .unsupportedRegion)
        #expect(WeatherProviderError.decoding("bad data").presentationKind == .decoding(message: "bad data"))
    }

    @Test("Nested provider failures recursively choose authentication when present")
    func nestedProviderFailurePresentationIsRecursive() {
        let error = WeatherProviderError.allProvidersFailed([
            WeatherProviderFailure(
                provider: "WeatherKitProvider",
                error: .network("offline")
            ),
            WeatherProviderFailure(
                provider: "NestedFallback",
                error: .allProvidersFailed([
                    WeatherProviderFailure(
                        provider: "Cache",
                        error: .decoding("corrupt")
                    ),
                    WeatherProviderFailure(
                        provider: "EntitledProvider",
                        error: .authentication
                    ),
                ])
            ),
        ])

        #expect(error.presentationKind == .authentication)
    }

    @Test("Nested provider failures preserve the first non-authentication leaf")
    func nestedProviderFailurePreservesFirstLeaf() {
        let error = WeatherProviderError.allProvidersFailed([
            WeatherProviderFailure(
                provider: "NestedPrimary",
                error: .allProvidersFailed([
                    WeatherProviderFailure(
                        provider: "Primary",
                        error: .rateLimited(retryAfter: 45)
                    ),
                ])
            ),
            WeatherProviderFailure(
                provider: "Fallback",
                error: .serviceUnavailable
            ),
        ])

        #expect(error.presentationKind == .rateLimited(retryAfter: 45))
        #expect(WeatherProviderError.allProvidersFailed([]).presentationKind == .serviceUnavailable)
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

    @MainActor
    @Test("Same-key best-bait requests coalesce into one model call")
    func sameKeyBaitRequestsCoalesce() async throws {
        let started = AsyncStartSignal()
        let calls = AsyncCounter()
        let context = try #require(Self.baitContext(locationOffset: 0))
        let engine = BaitEngine(
            modelAvailability: { .available },
            recommendationWorker: { _ in
                await calls.increment()
                await started.markStarted()
                try await Task.sleep(for: .milliseconds(80))
                return Self.baitRecommendation("Coalesced bait")
            }
        )

        let first = Task {
            await engine.generateBestBait(for: .bass, context: context)
        }
        await started.wait()
        let second = Task {
            await engine.generateBestBait(for: .bass, context: context)
        }
        await first.value
        await second.value

        #expect(await calls.value == 1)
        #expect(engine.result?.recommendation.topBait == "Coalesced bait")
    }

    @MainActor
    @Test("Changed prompt input bypasses a cached best-bait result")
    func changedPromptBypassesCachedBaitResult() async throws {
        let calls = AsyncCounter()
        let first = try #require(Self.baitContext(
            locationOffset: 0,
            biteScore: 70
        ))
        let reweighted = try #require(Self.baitContext(
            locationOffset: 0,
            biteScore: 71
        ))
        let engine = BaitEngine(
            modelAvailability: { .available },
            recommendationWorker: { context in
                await calls.increment()
                return Self.baitRecommendation(
                    "Score \(context.forecastPoint.biteScore ?? -1) bait"
                )
            }
        )

        await engine.generateBestBait(for: .bass, context: first)
        await engine.generateBestBait(for: .bass, context: reweighted)

        #expect(await calls.value == 2)
        #expect(engine.result?.key == reweighted.key)
        #expect(engine.result?.recommendation.topBait == "Score 71 bait")
    }

    @MainActor
    @Test("Changed prompt input does not coalesce with in-flight bait work")
    func changedPromptDoesNotCoalesceInflightBait() async throws {
        let oldStarted = AsyncStartSignal()
        let calls = AsyncCounter()
        let oldContext = try #require(Self.baitContext(
            locationOffset: 0,
            biteScore: 70
        ))
        let reweighted = try #require(Self.baitContext(
            locationOffset: 0,
            biteScore: 71
        ))
        let engine = BaitEngine(
            modelAvailability: { .available },
            recommendationWorker: { context in
                await calls.increment()
                if context.forecastPoint.biteScore == 70 {
                    await oldStarted.markStarted()
                    try? await Task.sleep(for: .milliseconds(100))
                    return Self.baitRecommendation("Old score bait")
                }
                return Self.baitRecommendation("Reweighted bait")
            }
        )

        let old = Task {
            await engine.generateBestBait(for: .bass, context: oldContext)
        }
        await oldStarted.wait()
        await engine.generateBestBait(for: .bass, context: reweighted)
        await old.value

        #expect(await calls.value == 2)
        #expect(engine.result?.key == reweighted.key)
        #expect(engine.result?.recommendation.topBait == "Reweighted bait")
    }

    @MainActor
    @Test("A stale best-bait success cannot replace a newer context")
    func staleBaitSuccessDoesNotCommit() async throws {
        let oldStarted = AsyncStartSignal()
        let oldContext = try #require(Self.baitContext(locationOffset: 0))
        let newContext = try #require(Self.baitContext(locationOffset: 1))
        let engine = BaitEngine(
            modelAvailability: { .available },
            recommendationWorker: { context in
                if context.key == oldContext.key {
                    await oldStarted.markStarted()
                    try? await Task.sleep(for: .milliseconds(100))
                    return Self.baitRecommendation("Old bait")
                }
                return Self.baitRecommendation("New bait")
            }
        )

        let old = Task {
            await engine.generateBestBait(for: .bass, context: oldContext)
        }
        await oldStarted.wait()
        await engine.generateBestBait(for: .bass, context: newContext)
        await old.value

        #expect(engine.result?.key == newContext.key)
        #expect(engine.result?.recommendation.topBait == "New bait")
        #expect(engine.result?.sourceLabel == "On-device Apple Intelligence")
    }

    @MainActor
    @Test("A stale model failure fallback cannot replace a newer success")
    func staleBaitFailureFallbackDoesNotCommit() async throws {
        let oldStarted = AsyncStartSignal()
        let oldContext = try #require(Self.baitContext(locationOffset: 0))
        let newContext = try #require(Self.baitContext(locationOffset: 1))
        let engine = BaitEngine(
            modelAvailability: { .available },
            recommendationWorker: { context in
                if context.key == oldContext.key {
                    await oldStarted.markStarted()
                    try? await Task.sleep(for: .milliseconds(100))
                    throw AsyncBaitError.failed
                }
                return Self.baitRecommendation("New bait")
            }
        )

        let old = Task {
            await engine.generateBestBait(for: .bass, context: oldContext)
        }
        await oldStarted.wait()
        await engine.generateBestBait(for: .bass, context: newContext)
        await old.value

        #expect(engine.result?.key == newContext.key)
        #expect(engine.result?.recommendation.topBait == "New bait")
        #expect(engine.result?.sourceLabel == "On-device Apple Intelligence")
    }

    @MainActor
    @Test("A new unavailable attempt wins over stale model work")
    func unavailableBaitAttemptInvalidatesInflightWork() async throws {
        let oldStarted = AsyncStartSignal()
        let oldContext = try #require(Self.baitContext(locationOffset: 0))
        let newContext = try #require(Self.baitContext(locationOffset: 1))
        let availability = BaitAvailabilityBox(.available)
        let engine = BaitEngine(
            modelAvailability: { availability.value },
            recommendationWorker: { context in
                if context.key == oldContext.key {
                    await oldStarted.markStarted()
                    try? await Task.sleep(for: .milliseconds(100))
                }
                return Self.baitRecommendation("Old bait")
            }
        )

        let old = Task {
            await engine.generateBestBait(for: .bass, context: oldContext)
        }
        await oldStarted.wait()
        availability.value = .unavailable("Disabled")
        await engine.generateBestBait(for: .bass, context: newContext)
        await old.value

        #expect(engine.result?.key == newContext.key)
        #expect(
            engine.result?.sourceLabel
                == "General species guidance — not adjusted for today"
        )
        #expect(engine.result?.recommendation.topBait != "Old bait")
    }

    @MainActor
    @Test("Same-key unavailability invalidates in-flight model work")
    func sameKeyUnavailabilityInvalidatesInflightWork() async throws {
        let oldStarted = AsyncStartSignal()
        let context = try #require(Self.baitContext(locationOffset: 0))
        let availability = BaitAvailabilityBox(.available)
        let engine = BaitEngine(
            modelAvailability: { availability.value },
            recommendationWorker: { _ in
                await oldStarted.markStarted()
                try? await Task.sleep(for: .milliseconds(100))
                return Self.baitRecommendation("Old bait")
            }
        )

        let old = Task {
            await engine.generateBestBait(for: .bass, context: context)
        }
        await oldStarted.wait()
        availability.value = .unavailable("Disabled")
        await engine.generateBestBait(for: .bass, context: context)
        await old.value

        #expect(engine.result?.key == context.key)
        #expect(
            engine.result?.sourceLabel
                == "General species guidance — not adjusted for today"
        )
        #expect(engine.result?.recommendation.topBait != "Old bait")
    }

    @MainActor
    @Test("All-species attempt invalidates in-flight best-bait work")
    func allSpeciesInvalidatesInflightBait() async throws {
        let started = AsyncStartSignal()
        let context = try #require(Self.baitContext(locationOffset: 0))
        let engine = BaitEngine(
            modelAvailability: { .available },
            recommendationWorker: { _ in
                await started.markStarted()
                try? await Task.sleep(for: .milliseconds(100))
                return Self.baitRecommendation("Old bait")
            }
        )

        let old = Task {
            await engine.generateBestBait(for: .bass, context: context)
        }
        await started.wait()
        await engine.generateBestBait(for: .all, context: nil)
        await old.value

        #expect(engine.status == .chooseSpecies)
        #expect(engine.result == nil)
        #expect(engine.answers.isEmpty)
        #expect(!engine.isAnswering)
    }

    @MainActor
    @Test("A new best-bait context drops an old Q and A response")
    func newBaitContextDropsInflightAnswer() async throws {
        let answerStarted = AsyncStartSignal()
        let oldContext = try #require(Self.baitContext(locationOffset: 0))
        let newContext = try #require(Self.baitContext(locationOffset: 1))
        let engine = BaitEngine(
            modelAvailability: { .available },
            recommendationWorker: { context in
                Self.baitRecommendation(
                    context.key == oldContext.key ? "Old bait" : "New bait"
                )
            },
            answerWorker: { _ in
                await answerStarted.markStarted()
                try? await Task.sleep(for: .milliseconds(100))
                return "Stale answer"
            }
        )

        await engine.generateBestBait(for: .bass, context: oldContext)
        let answer = Task { await engine.ask("old question") }
        await answerStarted.wait()
        await engine.generateBestBait(
            for: .bass,
            context: newContext,
            force: true
        )
        await answer.value

        #expect(engine.result?.key == newContext.key)
        #expect(engine.answers.isEmpty)
        #expect(!engine.isAnswering)
    }

    @MainActor
    @Test("Reset clears the complete best-bait session state")
    func resetClearsBestBaitState() async throws {
        let context = try #require(Self.baitContext(locationOffset: 0))
        let engine = BaitEngine(
            modelAvailability: { .available },
            recommendationWorker: { _ in Self.baitRecommendation("Bait") },
            answerWorker: { _ in "Answer" }
        )

        await engine.generateBestBait(for: .bass, context: context)
        await engine.ask("Question")
        engine.reset()

        #expect(engine.status == .idle)
        #expect(engine.result == nil)
        #expect(engine.report == nil)
        #expect(engine.adviceError == nil)
        #expect(!engine.isGeneratingAdvice)
        #expect(engine.answers.isEmpty)
        #expect(!engine.isAnswering)
        #expect(!engine.canAnswer)
    }

    @MainActor
    @Test("Advice for an old context cannot return after a new bait pick")
    func staleMoreAdviceDoesNotCommit() async throws {
        let adviceStarted = AsyncStartSignal()
        let oldContext = try #require(Self.baitContext(locationOffset: 0))
        let newContext = try #require(Self.baitContext(locationOffset: 1))
        let engine = BaitEngine(
            modelAvailability: { .available },
            recommendationWorker: { context in
                Self.baitRecommendation(
                    context.key == oldContext.key ? "Old bait" : "New bait"
                )
            },
            adviceWorker: { _, _ in
                await adviceStarted.markStarted()
                try? await Task.sleep(for: .milliseconds(100))
                return "Stale report"
            }
        )

        await engine.generateBestBait(for: .bass, context: oldContext)
        let oldAdvice = Task {
            await engine.generateMoreAdvice(for: oldContext)
        }
        await adviceStarted.wait()
        await engine.generateBestBait(
            for: .bass,
            context: newContext,
            force: true
        )
        await oldAdvice.value

        #expect(engine.result?.key == newContext.key)
        #expect(engine.report == nil)
    }

    private static func baitContext(
        locationOffset: Double,
        biteScore: Int? = 70
    ) -> BestBaitContext? {
        let date = Date(timeIntervalSince1970: 3_600)
        let point = ForecastPoint(
            weather: HourlyWeatherPoint(
                date: date,
                temperatureCelsius: 24,
                apparentTemperatureCelsius: 25,
                dewPointCelsius: 18,
                humidityFraction: 0.7,
                pressureHPa: 1_012,
                visibilityMeters: 16_000,
                uvIndex: 4,
                cloudCoverFraction: 0.2,
                precipitationChance: 0.1,
                precipitationMM: 0,
                conditionText: "Clear",
                symbolName: "sun.max",
                wind: WindSnapshot(
                    directionDegrees: 180,
                    speedMetersPerSecond: 4,
                    gustMetersPerSecond: nil
                )
            ),
            biteScore: biteScore,
            tideHeightFeet: nil,
            tidePhase: nil,
            solunarWindow: nil
        )
        return BestBaitContext(
            species: .bass,
            coordinate: CLLocationCoordinate2D(
                latitude: 30 + locationOffset,
                longitude: -86
            ),
            weatherFetchedAt: Date(timeIntervalSince1970: 100),
            tideFingerprint: "none",
            forecastPoint: point
        )
    }

    private static func baitRecommendation(_ name: String) -> BaitRecommendation {
        BaitRecommendation(
            topBait: name,
            color: "Natural",
            technique: "Slow retrieve",
            depth: "4 ft",
            confidence: 80,
            whyReason: "Selected-hour conditions support this pick."
        )
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

    func next() -> Int {
        value += 1
        return value
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

private enum AsyncBaitError: Error {
    case failed
}

private enum AsyncWeatherError: Error {
    case offline
}

@MainActor
private final class BaitAvailabilityBox {
    var value: BaitEngine.ModelAvailability

    init(_ value: BaitEngine.ModelAvailability) {
        self.value = value
    }
}
