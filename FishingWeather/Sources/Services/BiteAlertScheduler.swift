import Foundation

/// Local notifications cannot carry WeatherKit's required combined mark and
/// legal link. Weather-derived notifications therefore stay inside the NWS
/// attribution boundary; Apple-derived guidance remains in attributed app UI.
enum WeatherDerivedNotificationPolicy {
    static func allows(
        _ provenance: WeatherProvenance?,
        at date: Date = .now
    ) -> Bool {
        guard let provenance,
              provenance.isValid(at: date),
              let attribution = provenance.providerAttribution else {
            return false
        }
        return attribution.providerKind == .nationalWeatherService
            && attribution.hasRequiredSecureMetadata
    }

    /// A notification is useful only while the exact attributed forecast used
    /// to derive it is still valid. The strict upper bound prevents delivery
    /// at the provider expiry instant.
    static func allows(
        fireDate: Date,
        from provenance: WeatherProvenance?,
        at date: Date = .now
    ) -> Bool {
        guard allows(provenance, at: date),
              let provenance else { return false }
        return fireDate > date && fireDate < provenance.expiresAt
    }

    static func requiresClear(
        previousLocationKey: String?,
        newLocationKey: String
    ) -> Bool {
        guard let previousLocationKey,
              !previousLocationKey.isEmpty else { return true }
        return previousLocationKey != newLocationKey
    }

    static func scopeMatches(expected: String, active: String?) -> Bool {
        !expected.isEmpty && expected == active
    }
}

enum WeatherDerivedNotificationScope {
    static let storageKey = "weatherNotificationLocationKey"
    static let unavailable = "none"

    static func key(latitude: Double, longitude: Double) -> String {
        let lat = (latitude * 100).rounded() / 100
        let lon = (longitude * 100).rounded() / 100
        return "weather-\(lat),\(lon)"
    }

    static var activeKey: String? {
        UserDefaults.standard.string(forKey: storageKey)
    }

    static func isActive(_ expected: String) -> Bool {
        WeatherDerivedNotificationPolicy.scopeMatches(
            expected: expected,
            active: activeKey
        )
    }
}

enum WeatherDerivedNotificationIdentifiers {
    static let smartAlertPrefix = "bite-"
    static let nextWindow = "biteWindow.next"

    static func contains(_ identifier: String) -> Bool {
        identifier.hasPrefix(smartAlertPrefix) || identifier == nextWindow
    }
}

/// Turns a `WeekOutlook` into the set of bite-window notifications to schedule.
/// Pure and deterministic — the delivery layer (UNUserNotificationCenter) reads
/// this list; it holds no scheduling policy of its own.
enum BiteAlertScheduler {
    static func plan(
        from outlook: WeekOutlook,
        preferences prefs: AlertPreferences,
        provenance: WeatherProvenance,
        now: Date = .now
    ) -> [BiteAlert] {
        guard prefs.enabled,
              WeatherDerivedNotificationPolicy.allows(provenance, at: now)
        else { return [] }
        let lead = TimeInterval(prefs.leadMinutes * 60)

        return outlook.windows
            .filter { $0.confidence == .high && $0.score >= prefs.minScore }
            .compactMap { window -> BiteAlert? in
                let fireDate = window.start.addingTimeInterval(-lead)
                // Skip windows too close to fire usefully (or already past).
                guard WeatherDerivedNotificationPolicy.allows(
                    fireDate: fireDate,
                    from: provenance,
                    at: now
                ) else { return nil }
                return BiteAlert(
                    id: "bite-\(Int(window.start.timeIntervalSince1970))",
                    fireDate: fireDate,
                    windowStart: window.start,
                    score: window.score,
                    period: window.period,
                    title: "\(window.period.rawValue) bite window",
                    body: body(for: window, at: outlook.locationName)
                )
            }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(prefs.maxAlerts)
            .map { $0 }
    }

    private static func body(for window: ScoredWindow, at location: String) -> String {
        let time = window.start.formatted(date: .omitted, time: .shortened)
        let why = window.factors.prefix(2).joined(separator: ", ")
        let tail = why.isEmpty ? "" : " \(why)."
        return "\(window.species.displayName) · score \(window.score) at \(location), \(time).\(tail)"
    }
}
