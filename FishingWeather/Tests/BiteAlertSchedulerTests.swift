import Foundation
import Testing
@testable import BiteCast

@Suite("BiteAlertScheduler")
struct BiteAlertSchedulerTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let enabled = AlertPreferences(enabled: true, minScore: 70,
                                           leadMinutes: 45, maxAlerts: 5)

    private var provenance: WeatherProvenance {
        WeatherProvenance(
            source: .nws,
            fetchedAt: now,
            isFallback: false,
            attribution: "National Weather Service",
            providerAttribution: .nationalWeatherService,
            expiresAt: now.addingTimeInterval(12 * 3_600)
        )
    }

    private func window(hoursFromNow: Double, score: Int,
                        confidence: ScoredWindow.Confidence = .high,
                        period: BitePeriod = .major) -> ScoredWindow {
        let start = now.addingTimeInterval(hoursFromNow * 3600)
        return ScoredWindow(
            date: start, start: start, end: start.addingTimeInterval(3600),
            score: score, confidence: confidence, period: period,
            factors: ["Major window", "Falling pressure"], species: .redfish
        )
    }

    private func outlook(_ windows: [ScoredWindow]) -> WeekOutlook {
        WeekOutlook(locationName: "Fort De Soto", generatedAt: now, windows: windows)
    }

    @Test("Disabled preferences schedule nothing")
    func disabledYieldsNoAlerts() {
        var prefs = enabled; prefs.enabled = false
        let alerts = BiteAlertScheduler.plan(
            from: outlook([window(hoursFromNow: 5, score: 90)]),
            preferences: prefs,
            provenance: provenance,
            now: now
        )
        #expect(alerts.isEmpty)
    }

    @Test("Only windows at or above the min score alert")
    func filtersBelowMinScore() {
        let alerts = BiteAlertScheduler.plan(from: outlook([
            window(hoursFromNow: 5, score: 60),
            window(hoursFromNow: 6, score: 85),
        ]), preferences: enabled, provenance: provenance, now: now)
        #expect(alerts.count == 1)
        #expect(alerts.first?.score == 85)
    }

    @Test("Low-confidence windows are excluded")
    func onlyHighConfidence() {
        let alerts = BiteAlertScheduler.plan(from: outlook([
            window(hoursFromNow: 5, score: 90, confidence: .low),
        ]), preferences: enabled, provenance: provenance, now: now)
        #expect(alerts.isEmpty)
    }

    @Test("Fire date is the lead time before the window start")
    func fireDateIsLeadBeforeStart() {
        let w = window(hoursFromNow: 5, score: 90)
        let alerts = BiteAlertScheduler.plan(
            from: outlook([w]),
            preferences: enabled,
            provenance: provenance,
            now: now
        )
        #expect(alerts.first?.fireDate == w.start.addingTimeInterval(-45 * 60))
    }

    @Test("Windows whose lead time already passed are skipped")
    func excludesPastFireDates() {
        // 30 min out, but the 45-min lead puts the fire date in the past.
        let alerts = BiteAlertScheduler.plan(
            from: outlook([window(hoursFromNow: 0.5, score: 90)]),
            preferences: enabled,
            provenance: provenance,
            now: now
        )
        #expect(alerts.isEmpty)
    }

    @Test("Output is capped and sorted by fire date, keeping the soonest")
    func cappedAndSorted() {
        let hours: [Double] = [8, 3, 11, 5, 2, 9]
        let windows = hours.map { window(hoursFromNow: $0, score: 80) }
        var prefs = enabled; prefs.maxAlerts = 3
        let alerts = BiteAlertScheduler.plan(
            from: outlook(windows),
            preferences: prefs,
            provenance: provenance,
            now: now
        )
        #expect(alerts.count == 3)
        #expect(alerts.map(\.fireDate) == alerts.map(\.fireDate).sorted())
        #expect(alerts.first?.windowStart == now.addingTimeInterval(2 * 3600))
    }

    @Test("Weather-derived local notifications require an unexpired NWS forecast")
    func notificationComplianceBoundary() {
        let nws = WeatherProvenance(
            source: .nws,
            fetchedAt: now,
            isFallback: true,
            attribution: "National Weather Service",
            providerAttribution: .nationalWeatherService,
            expiresAt: now.addingTimeInterval(1_800)
        )
        let apple = WeatherProvenance(
            source: .weatherKit,
            fetchedAt: now,
            isFallback: false,
            attribution: "Apple Weather",
            providerAttribution: WeatherProviderAttribution(
                providerKind: .appleWeather,
                serviceName: "Apple Weather",
                legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
                combinedMarkLightURL: URL(string: "https://weatherkit.apple.com/light.png")!,
                combinedMarkDarkURL: URL(string: "https://weatherkit.apple.com/dark.png")!,
                legalText: "Weather data sources and legal attribution"
            ),
            expiresAt: now.addingTimeInterval(1_800)
        )

        #expect(WeatherDerivedNotificationPolicy.allows(nws, at: now))
        #expect(!WeatherDerivedNotificationPolicy.allows(nws, at: nws.expiresAt))
        #expect(!WeatherDerivedNotificationPolicy.allows(apple, at: now))
        #expect(!WeatherDerivedNotificationPolicy.allows(nil, at: now))

        let beforeExpiry = nws.expiresAt.addingTimeInterval(-1)
        #expect(WeatherDerivedNotificationPolicy.allows(
            fireDate: beforeExpiry,
            from: nws,
            at: now
        ))
        #expect(!WeatherDerivedNotificationPolicy.allows(
            fireDate: nws.expiresAt,
            from: nws,
            at: now
        ))
        #expect(!WeatherDerivedNotificationPolicy.allows(
            fireDate: now,
            from: nws,
            at: now
        ))
    }

    @Test("Smart alerts cannot fire at or after provider expiry")
    func alertsDoNotOutliveProvenance() throws {
        let shortProvenance = WeatherProvenance(
            source: .nws,
            fetchedAt: now,
            isFallback: false,
            attribution: "National Weather Service",
            providerAttribution: .nationalWeatherService,
            expiresAt: now.addingTimeInterval(4 * 3_600)
        )

        let alerts = BiteAlertScheduler.plan(
            from: outlook([
                window(hoursFromNow: 3, score: 90),
                window(hoursFromNow: 5, score: 95),
            ]),
            preferences: enabled,
            provenance: shortProvenance,
            now: now
        )

        #expect(alerts.count == 1)
        #expect(alerts.allSatisfy { $0.fireDate < shortProvenance.expiresAt })

        #expect(BiteAlertNotifier.alertsEligibleForCommit(
            alerts,
            provenance: shortProvenance,
            at: shortProvenance.expiresAt
        ).isEmpty)
        let first = try #require(alerts.first)
        #expect(BiteAlertNotifier.alertsEligibleForCommit(
            alerts,
            provenance: shortProvenance,
            at: first.fireDate
        ).isEmpty)
    }

    @Test("Both weather-derived notification identifier families are recognized")
    func weatherDerivedNotificationIdentifiers() {
        #expect(WeatherDerivedNotificationIdentifiers.contains("bite-123"))
        #expect(WeatherDerivedNotificationIdentifiers.contains("biteWindow.next"))
        #expect(!WeatherDerivedNotificationIdentifiers.contains("unrelated"))
    }

    @Test("A changed active location revokes reminders derived for the old location")
    func locationChangeRevokesWeatherNotifications() {
        #expect(WeatherDerivedNotificationPolicy.requiresClear(
            previousLocationKey: nil,
            newLocationKey: "spot-a"
        ))
        #expect(WeatherDerivedNotificationPolicy.requiresClear(
            previousLocationKey: "",
            newLocationKey: "spot-a"
        ))
        #expect(!WeatherDerivedNotificationPolicy.requiresClear(
            previousLocationKey: "spot-a",
            newLocationKey: "spot-a"
        ))
        #expect(WeatherDerivedNotificationPolicy.requiresClear(
            previousLocationKey: "spot-a",
            newLocationKey: "spot-b"
        ))
        #expect(WeatherDerivedNotificationPolicy.scopeMatches(
            expected: "weather-30.29,-86.0",
            active: "weather-30.29,-86.0"
        ))
        #expect(!WeatherDerivedNotificationPolicy.scopeMatches(
            expected: "weather-30.29,-86.0",
            active: "weather-40.0,-90.0"
        ))
    }
}
