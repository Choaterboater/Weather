import Foundation
import Testing
import UIKit
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

    @Test("Source attribution exposes the provider mark and accessible legal destination")
    func sourceAttributionAccessibilityContract() throws {
        let apple = WeatherProviderAttribution(
            providerKind: .appleWeather,
            serviceName: "Apple Weather",
            legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
            combinedMarkLightURL: URL(string: "https://weatherkit.apple.com/assets/light.png")!,
            combinedMarkDarkURL: URL(string: "https://weatherkit.apple.com/assets/dark.png")!,
            legalText: "Weather data sources and legal attribution"
        )
        let presentation = WeatherSourceAttributionPresentation.make(apple)

        #expect(presentation?.serviceName == "Apple Weather")
        #expect(presentation?.legalLinkLabel == "Apple Weather legal attribution")
        #expect(presentation?.accessibilityLabel == "Weather source, Apple Weather")
        #expect(presentation?.lightMarkURL == apple.combinedMarkLightURL)
        #expect(presentation?.darkMarkURL == apple.combinedMarkDarkURL)

        let nws = try #require(WeatherSourceAttributionPresentation.make(.nationalWeatherService))
        #expect(nws.legalLinkLabel == "National Weather Service source")
        #expect(nws.accessibilityLabel == "Weather source, National Weather Service")
        #expect(nws.lightMarkURL == nil)
        #expect(nws.darkMarkURL == nil)
    }

    @Test("Source attribution never presents an insecure legal destination")
    func sourceAttributionRequiresHTTPS() {
        let insecure = WeatherProviderAttribution(
            providerKind: .nationalWeatherService,
            serviceName: "National Weather Service",
            legalPageURL: URL(string: "http://weather.gov/")!,
            combinedMarkLightURL: nil,
            combinedMarkDarkURL: nil,
            legalText: "Weather data provided by the National Weather Service."
        )

        #expect(WeatherSourceAttributionPresentation.make(insecure) == nil)
    }

    @MainActor
    @Test("Dark preview uses the provider's visible white combined mark")
    func previewAppleMarksMatchAppearanceContrast() throws {
        let attribution = DebugWeatherFixtureAttribution.apple
        let lightData = try #require(attribution.combinedMarkLightData)
        let darkData = try #require(attribution.combinedMarkDarkData)

        #expect(attribution.combinedMarkLightURL?.lastPathComponent.contains("blk") == true)
        #expect(attribution.combinedMarkDarkURL?.lastPathComponent.contains("wht") == true)
        #expect(try #require(opaqueLuminance(lightData)) < 0.25)
        #expect(try #require(opaqueLuminance(darkData)) > 0.75)
    }

    @Test("Fishing forecast safety copy is informational and rejects life-safety claims")
    func safetyNoticeContract() {
        #expect(ForecastSafetyNoticeContent.title == "Forecast guidance only")
        #expect(ForecastSafetyNoticeContent.message.localizedCaseInsensitiveContains("informational"))
        #expect(ForecastSafetyNoticeContent.message.localizedCaseInsensitiveContains("official alerts"))
        #expect(!ForecastSafetyNoticeContent.message.localizedCaseInsensitiveContains("safe to navigate"))
        #expect(!ForecastSafetyNoticeContent.message.localizedCaseInsensitiveContains("emergency service"))
    }

    @Test("Apple value-added fishing guidance discloses that provider data was modified")
    func appleDerivedDataNoticeContract() {
        #expect(ModifiedWeatherDataNoticeContent.isRequired(
            for: DebugWeatherFixtureAttribution.apple
        ))
        #expect(!ModifiedWeatherDataNoticeContent.isRequired(
            for: .nationalWeatherService
        ))
        #expect(
            ModifiedWeatherDataNoticeContent.message
                .localizedCaseInsensitiveContains("modified")
        )
        #expect(
            ModifiedWeatherDataNoticeContent.message
                .localizedCaseInsensitiveContains("Apple Weather")
        )
    }

    @Test("Derived forecast screens stop displaying at the exact provider expiry")
    func derivedContentExpiryBoundary() {
        let provenance = WeatherProvenance(
            source: .nws,
            fetchedAt: now,
            isFallback: true,
            attribution: "National Weather Service",
            providerAttribution: .nationalWeatherService,
            expiresAt: now.addingTimeInterval(30)
        )

        #expect(WeatherDerivedContentPolicy.canDisplay(
            provenance,
            at: now.addingTimeInterval(29)
        ))
        #expect(!WeatherDerivedContentPolicy.canDisplay(
            provenance,
            at: provenance.expiresAt
        ))
        #expect(WeatherDerivedContentPolicy.secondsUntilExpiry(
            provenance,
            at: now
        ) == 30)
        #expect(WeatherDerivedContentPolicy.secondsUntilExpiry(
            provenance,
            at: provenance.expiresAt
        ) == nil)
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

    private func opaqueLuminance(_ data: Data) -> Double? {
        guard let cgImage = UIImage(data: data)?.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard didDraw else { return nil }

        var total = 0.0
        var opaquePixelCount = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            guard pixels[index + 3] >= 64 else { continue }
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            total += 0.2126 * red + 0.7152 * green + 0.0722 * blue
            opaquePixelCount += 1
        }
        guard opaquePixelCount > 0 else { return nil }
        return total / Double(opaquePixelCount)
    }
}
