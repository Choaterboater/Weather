import Foundation
import Testing
@testable import BiteCast

@Suite("BiteTime presentation")
struct BiteTimePresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Weather sources are named truthfully with deterministic freshness")
    func sourceAndFreshnessLabels() {
        let live = BiteTimeSourcePresentation.make(
            provenance: WeatherProvenance(
                source: .weatherKit,
                fetchedAt: now.addingTimeInterval(-20),
                isFallback: false,
                attribution: "Apple Weather"
            ),
            now: now,
            timeZone: .gmt,
            locale: Locale(identifier: "en_US_POSIX")
        )
        #expect(live.title == "Apple Weather")
        #expect(live.freshness == "Updated just now")
        #expect(!live.title.localizedCaseInsensitiveContains("cache"))

        let nws = BiteTimeSourcePresentation.make(
            provenance: WeatherProvenance(
                source: .nws,
                fetchedAt: now.addingTimeInterval(-12 * 60),
                isFallback: true,
                attribution: "National Weather Service"
            ),
            now: now,
            timeZone: .gmt,
            locale: Locale(identifier: "en_US_POSIX")
        )
        #expect(nws.title == "National Weather Service fallback")
        #expect(nws.freshness == "Updated 12 min ago")

        let cache = BiteTimeSourcePresentation.make(
            provenance: WeatherProvenance(
                source: .cache,
                fetchedAt: now.addingTimeInterval(-2 * 3_600),
                isFallback: true,
                attribution: "Cached from National Weather Service"
            ),
            now: now,
            timeZone: .gmt,
            locale: Locale(identifier: "en_US_POSIX")
        )
        #expect(cache.title == "Cached forecast")
        #expect(cache.freshness == "Cached 2 hr ago")
        #expect(cache.detail == "Cached from National Weather Service")
        #expect(!cache.title.localizedCaseInsensitiveContains("live"))
    }

    @Test("Old source timestamps use the forecast time zone and locale")
    func oldSourceTimestampUsesForecastContext() {
        let chicago = TimeZone(identifier: "America/Chicago")!
        let value = BiteTimeSourcePresentation.make(
            provenance: WeatherProvenance(
                source: .nws,
                fetchedAt: now.addingTimeInterval(-30 * 3_600),
                isFallback: false,
                attribution: "National Weather Service"
            ),
            now: now,
            timeZone: chicago,
            locale: Locale(identifier: "en_US_POSIX")
        )

        #expect(value.freshness.hasPrefix("Updated "))
        #expect(value.freshness.contains(" at "))
    }

    @Test("Nested provider failures retain a typed presentation category")
    func nestedProviderFailuresAreClassified() {
        let authentication = WeatherProviderError.allProvidersFailed([
            WeatherProviderFailure(
                provider: "Outer",
                error: .allProvidersFailed([
                    WeatherProviderFailure(
                        provider: "WeatherKit",
                        error: .authentication
                    )
                ])
            )
        ])
        #expect(authentication.presentationKind == .authentication)

        let network = WeatherProviderError.allProvidersFailed([
            WeatherProviderFailure(
                provider: "WeatherKit",
                error: .network("offline")
            ),
            WeatherProviderFailure(
                provider: "NWS",
                error: .serviceUnavailable
            ),
        ])
        #expect(network.presentationKind == .network(message: "offline"))

        #expect(
            WeatherProviderError.rateLimited(retryAfter: 90).presentationKind
                == .rateLimited(retryAfter: 90)
        )
        #expect(
            WeatherProviderError.unsupportedRegion.presentationKind
                == .unsupportedRegion
        )
        #expect(
            WeatherProviderError.decoding("bad payload").presentationKind
                == .decoding(message: "bad payload")
        )
    }

    @Test("Current decision uses the captured clock and never calls stale cache current")
    func currentDecisionUsesCapturedNowAndFreshness() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let sameHour = now.addingTimeInterval(20 * 60)

        let live = WeatherProvenance(
            source: .nws,
            fetchedAt: now.addingTimeInterval(-8 * 60),
            isFallback: true,
            attribution: "National Weather Service"
        )
        #expect(
            BiteTimeCurrentDecision.isCurrent(
                pointDate: sameHour,
                capturedNow: now,
                provenance: live,
                calendar: calendar
            )
        )

        #expect(
            !BiteTimeCurrentDecision.isCurrent(
                pointDate: now.addingTimeInterval(-3 * 3_600),
                capturedNow: now,
                provenance: live,
                calendar: calendar
            )
        )

        let staleCache = WeatherProvenance(
            source: .cache,
            fetchedAt: now.addingTimeInterval(-2 * 3_600),
            isFallback: true,
            attribution: "Cached from National Weather Service"
        )
        #expect(
            !BiteTimeCurrentDecision.isCurrent(
                pointDate: sameHour,
                capturedNow: now,
                provenance: staleCache,
                calendar: calendar
            )
        )

        let justFreshCache = WeatherProvenance(
            source: .cache,
            fetchedAt: now.addingTimeInterval(
                -BiteTimeCurrentDecision.maximumCurrentCacheAge + 1
            ),
            isFallback: true,
            attribution: "Cached from National Weather Service"
        )
        #expect(
            BiteTimeCurrentDecision.isCurrent(
                pointDate: sameHour,
                capturedNow: now,
                provenance: justFreshCache,
                calendar: calendar
            )
        )

        let expiredAtBoundary = WeatherProvenance(
            source: .cache,
            fetchedAt: now.addingTimeInterval(
                -BiteTimeCurrentDecision.maximumCurrentCacheAge
            ),
            isFallback: true,
            attribution: "Cached from National Weather Service"
        )
        #expect(
            !BiteTimeCurrentDecision.isCurrent(
                pointDate: sameHour,
                capturedNow: now,
                provenance: expiredAtBoundary,
                calendar: calendar
            )
        )
    }

    @Test("Current decision distinguishes the repeated daylight-saving hour")
    func currentDecisionDistinguishesRepeatedHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(
            TimeZone(identifier: "America/New_York")
        )
        let formatter = ISO8601DateFormatter()
        let firstHour = try #require(
            formatter.date(from: "2030-11-03T01:15:00-04:00")
        )
        let firstHourPoint = try #require(
            formatter.date(from: "2030-11-03T01:45:00-04:00")
        )
        let repeatedHourPoint = try #require(
            formatter.date(from: "2030-11-03T01:30:00-05:00")
        )
        let provenance = WeatherProvenance(
            source: .nws,
            fetchedAt: firstHour,
            isFallback: false,
            attribution: "National Weather Service"
        )

        #expect(BiteTimeCurrentDecision.isCurrent(
            pointDate: firstHourPoint,
            capturedNow: firstHour,
            provenance: provenance,
            calendar: calendar
        ))
        #expect(!BiteTimeCurrentDecision.isCurrent(
            pointDate: repeatedHourPoint,
            capturedNow: firstHour,
            provenance: provenance,
            calendar: calendar
        ))
    }

    @Test("Saved location accessibility retains its descriptive subtitle")
    func savedLocationAccessibilityRetainsSubtitle() {
        let value = BiteTimeLocationAccessibility.make(
            title: "St. Petersburg Pier",
            subtitle: "Pier · FL"
        )

        #expect(value.label == "Fishing location, St. Petersburg Pier")
        #expect(value.value == "Pier · FL")
    }

    @Test("NWS debug fixture traverses authentication fallback chain")
    func nwsDebugFixtureUsesProviderChain() async throws {
        let result = try await BiteTimePreviewProviderChainFixture.run()
        let snapshot = result.snapshot

        #expect(result.attempts == ["WeatherKit", "NWS"])
        #expect(snapshot.provenance.source == .nws)
        #expect(snapshot.provenance.isFallback)
        #expect(snapshot.provenance.attribution == "National Weather Service")
    }

    @Test("Selected tide day slices the retained range in the forecast calendar")
    func selectedTideDayUsesRetainedForecastRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(
            TimeZone(identifier: "Pacific/Honolulu")
        )
        let firstDay = try #require(calendar.date(
            from: DateComponents(year: 2030, month: 7, day: 13, hour: 9)
        ))
        let selectedDay = try #require(calendar.date(
            from: DateComponents(year: 2030, month: 7, day: 14, hour: 9)
        ))
        let allEvents = [
            TideEvent(time: firstDay, kind: .high, heightFeet: 3.2),
            TideEvent(time: selectedDay, kind: .low, heightFeet: 0.8),
        ]
        let allSamples = [
            TideSample(time: firstDay, heightFeet: 3.2),
            TideSample(time: selectedDay, heightFeet: 0.8),
        ]
        let snapshot = BiteTimeTideSnapshot(
            events: [allEvents[0]],
            allEvents: allEvents,
            samples: [allSamples[0]],
            allSamples: allSamples,
            stationName: "Fixture station",
            distanceMiles: 1.5
        )

        let value = snapshot.selecting(selectedDay, calendar: calendar)

        #expect(value.events == [allEvents[1]])
        #expect(value.samples == [allSamples[1]])
        #expect(value.allEvents == allEvents)
        #expect(value.allSamples == allSamples)
    }

    @Test("Programmatic reset does not fire selection feedback")
    func resetHasNoHapticIdentity() {
        let dates = [0, 1, 2].map {
            now.addingTimeInterval(Double($0) * 3_600)
        }
        var state = BiteTimeSelectionState()

        state.reset(around: now.addingTimeInterval(2_000), in: dates)
        #expect(state.selectedDate == dates[1])
        #expect(state.feedbackGeneration == 0)

        state.reset(around: dates[2], in: dates)
        #expect(state.selectedDate == dates[2])
        #expect(state.feedbackGeneration == 0)
    }

    @Test("Only a changed user-selected hour advances haptic identity")
    func userSelectionAdvancesHapticIdentityOnce() {
        let dates = [0, 1, 2].map {
            now.addingTimeInterval(Double($0) * 3_600)
        }
        var state = BiteTimeSelectionState()
        state.reset(around: dates[0], in: dates)

        state.selectByUser(dates[1].addingTimeInterval(100), in: dates)
        #expect(state.selectedDate == dates[1])
        #expect(state.feedbackGeneration == 1)

        state.selectByUser(dates[1], in: dates)
        #expect(state.feedbackGeneration == 1)

        state.reconcile(with: dates, around: dates[0])
        #expect(state.selectedDate == dates[1])
        #expect(state.feedbackGeneration == 1)
    }

    @Test("A removed provider hour resets silently to the nearest valid hour")
    func unavailableSelectionResetsSilently() {
        let dates = [0, 1, 2].map {
            now.addingTimeInterval(Double($0) * 3_600)
        }
        var state = BiteTimeSelectionState()
        state.reset(around: dates[1], in: dates)
        state.selectByUser(dates[2], in: dates)

        state.reconcile(with: Array(dates.prefix(2)), around: dates[0])

        #expect(state.selectedDate == dates[0])
        #expect(state.feedbackGeneration == 1)
    }
}
