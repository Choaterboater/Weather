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
