import Foundation

enum WeatherSource: String, Codable, Sendable {
    case weatherKit
    case nws
    case cache
}

enum WeatherProviderKind: String, Codable, Equatable, Sendable {
    case appleWeather
    case nationalWeatherService
}

/// Provider-supplied attribution persisted with the exact forecast it covers.
/// Apple mark URLs are optional at the model boundary because NWS has no
/// corresponding mark, but WeatherKit rejects its payload unless both marks
/// are present.
struct WeatherProviderAttribution: Codable, Equatable, Sendable {
    let providerKind: WeatherProviderKind
    let serviceName: String
    let legalPageURL: URL
    let combinedMarkLightURL: URL?
    let combinedMarkDarkURL: URL?
    let legalText: String?
    let combinedMarkLightData: Data?
    let combinedMarkDarkData: Data?

    init(
        providerKind: WeatherProviderKind,
        serviceName: String,
        legalPageURL: URL,
        combinedMarkLightURL: URL?,
        combinedMarkDarkURL: URL?,
        legalText: String?,
        combinedMarkLightData: Data? = nil,
        combinedMarkDarkData: Data? = nil
    ) {
        self.providerKind = providerKind
        self.serviceName = serviceName
        self.legalPageURL = legalPageURL
        self.combinedMarkLightURL = combinedMarkLightURL
        self.combinedMarkDarkURL = combinedMarkDarkURL
        self.legalText = legalText
        self.combinedMarkLightData = combinedMarkLightData
        self.combinedMarkDarkData = combinedMarkDarkData
    }

    static let nationalWeatherService = Self(
        providerKind: .nationalWeatherService,
        serviceName: "National Weather Service",
        legalPageURL: URL(string: "https://www.weather.gov/")!,
        combinedMarkLightURL: nil,
        combinedMarkDarkURL: nil,
        legalText: "Weather data provided by the National Weather Service.",
        combinedMarkLightData: nil,
        combinedMarkDarkData: nil
    )

    /// Provider links are rendered as tappable destinations and Apple mark
    /// locations are fetched by the app, so only authenticated HTTPS metadata
    /// is eligible to cross the provider/cache boundary.
    var hasRequiredSecureMetadata: Bool {
        let trimmedName = serviceName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let trimmedLegalText = legalText?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        guard !trimmedName.isEmpty,
              !trimmedLegalText.isEmpty,
              Self.isHTTPS(legalPageURL) else { return false }

        switch providerKind {
        case .appleWeather:
            guard let combinedMarkLightURL,
                  let combinedMarkDarkURL else { return false }
            return Self.isHTTPS(combinedMarkLightURL)
                && Self.isHTTPS(combinedMarkDarkURL)
        case .nationalWeatherService:
            return true
        }
    }

    private static func isHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host != nil
            && url.user == nil
            && url.password == nil
            && url.port == nil
            && url.query == nil
            && url.fragment == nil
    }
}

struct WeatherProvenance: Codable, Equatable, Sendable {
    let source: WeatherSource
    let fetchedAt: Date
    let isFallback: Bool
    let attribution: String?
    let providerAttribution: WeatherProviderAttribution?
    let expiresAt: Date

    init(
        source: WeatherSource,
        fetchedAt: Date,
        isFallback: Bool,
        attribution: String?,
        providerAttribution: WeatherProviderAttribution? = nil,
        expiresAt: Date? = nil
    ) {
        self.source = source
        self.fetchedAt = fetchedAt
        self.isFallback = isFallback
        self.attribution = attribution
        self.providerAttribution = providerAttribution
        // Compatibility default for deterministic fixtures and non-provider
        // callers. Live providers always supply their authoritative finite
        // expiration explicitly.
        self.expiresAt = expiresAt ?? fetchedAt.addingTimeInterval(24 * 3_600)
    }

    func isValid(at date: Date) -> Bool {
        fetchedAt.timeIntervalSinceReferenceDate.isFinite
            && expiresAt.timeIntervalSinceReferenceDate.isFinite
            && fetchedAt <= date
            && date < expiresAt
    }
}

struct WeatherSourceAttributionPresentation: Equatable, Sendable {
    let serviceName: String
    let legalURL: URL
    let legalLinkLabel: String
    let accessibilityLabel: String
    let lightMarkURL: URL?
    let darkMarkURL: URL?
    let lightMarkData: Data?
    let darkMarkData: Data?
    let legalText: String?

    static func make(_ attribution: WeatherProviderAttribution?) -> Self? {
        guard let attribution,
              attribution.hasRequiredSecureMetadata else { return nil }

        let linkLabel = switch attribution.providerKind {
        case .appleWeather: "Apple Weather legal attribution"
        case .nationalWeatherService: "National Weather Service source"
        }
        return Self(
            serviceName: attribution.serviceName,
            legalURL: attribution.legalPageURL,
            legalLinkLabel: linkLabel,
            accessibilityLabel: "Weather source, \(attribution.serviceName)",
            lightMarkURL: attribution.combinedMarkLightURL,
            darkMarkURL: attribution.combinedMarkDarkURL,
            lightMarkData: attribution.combinedMarkLightData,
            darkMarkData: attribution.combinedMarkDarkData,
            legalText: attribution.legalText
        )
    }
}

enum ForecastSafetyNoticeContent {
    static let title = "Forecast guidance only"
    static let message = "Weather and fishing guidance is informational. Check official alerts and local conditions before heading out."
}

/// Apple requires value-added products to make it clear when its weather data
/// has been transformed into new guidance. BiteCast shows this beside the
/// provider mark, before any score, bait, trip, or scouting recommendation.
enum ModifiedWeatherDataNoticeContent {
    static let title = "Derived fishing guidance"
    static let message = "Fishing guidance is modified from the original Apple Weather data."

    static func isRequired(
        for attribution: WeatherProviderAttribution
    ) -> Bool {
        attribution.providerKind == .appleWeather
    }
}

/// Shared exact-expiry boundary for screens that retain derived values after
/// navigation. A sleeping view task uses the delay and then invalidates its
/// local cards/reports even when no parent observation changes.
enum WeatherDerivedContentPolicy {
    static func canDisplay(
        _ provenance: WeatherProvenance,
        at date: Date = .now
    ) -> Bool {
        provenance.isValid(at: date)
    }

    static func secondsUntilExpiry(
        _ provenance: WeatherProvenance,
        at date: Date = .now
    ) -> TimeInterval? {
        guard canDisplay(provenance, at: date) else { return nil }
        return provenance.expiresAt.timeIntervalSince(date)
    }
}

struct WindSnapshot: Codable, Equatable, Sendable {
    let directionDegrees: Double
    let speedMetersPerSecond: Double
    let gustMetersPerSecond: Double?
}

struct CurrentConditionsSnapshot: Codable, Equatable, Sendable {
    let date: Date
    let temperatureCelsius: Double
    let apparentTemperatureCelsius: Double
    let dewPointCelsius: Double?
    let humidityFraction: Double?
    let pressureHPa: Double?
    let visibilityMeters: Double?
    let uvIndex: Int?
    let conditionText: String
    let symbolName: String
    let wind: WindSnapshot
}

struct HourlyWeatherPoint: Identifiable, Codable, Equatable, Sendable {
    var id: Date { date }

    let date: Date
    let temperatureCelsius: Double
    let apparentTemperatureCelsius: Double?
    let dewPointCelsius: Double?
    let humidityFraction: Double?
    let pressureHPa: Double?
    let visibilityMeters: Double?
    let uvIndex: Int?
    let cloudCoverFraction: Double?
    let precipitationChance: Double?
    let precipitationMM: Double?
    let conditionText: String
    let symbolName: String
    let wind: WindSnapshot
}

struct DailyWeatherPoint: Identifiable, Codable, Equatable, Sendable {
    var id: Date { date }

    let date: Date
    let lowCelsius: Double
    let highCelsius: Double
    let precipitationChance: Double?
    let conditionText: String
    let symbolName: String
    let windMetersPerSecond: Double?
    let windPeakMetersPerSecond: Double?
    let astronomy: AstronomySnapshot?
}

struct AstronomySnapshot: Codable, Equatable, Sendable {
    let sunrise: Date?
    let sunset: Date?
    let moonrise: Date?
    let moonset: Date?
    let moonTransit: Date?
    let moonPhaseFraction: Double?

    static let empty = Self(
        sunrise: nil,
        sunset: nil,
        moonrise: nil,
        moonset: nil,
        moonTransit: nil,
        moonPhaseFraction: nil
    )
}

struct WeatherCoordinate: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

struct WeatherAlertSnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let summary: String
    let source: String
    let severity: String?
    let startDate: Date?
    let endDate: Date?
    let detailsURL: URL?
}

struct WeatherSnapshot: Codable, Equatable, Sendable {
    let coordinate: WeatherCoordinate
    let timeZoneIdentifier: String
    let current: CurrentConditionsSnapshot
    let hourly: [HourlyWeatherPoint]
    let daily: [DailyWeatherPoint]
    let alerts: [WeatherAlertSnapshot]
    let astronomy: AstronomySnapshot
    let provenance: WeatherProvenance

    func markingFallback(_ isFallback: Bool) -> Self {
        guard isFallback, !provenance.isFallback else { return self }

        return Self(
            coordinate: coordinate,
            timeZoneIdentifier: timeZoneIdentifier,
            current: current,
            hourly: hourly,
            daily: daily,
            alerts: alerts,
            astronomy: astronomy,
            provenance: WeatherProvenance(
                source: provenance.source,
                fetchedAt: provenance.fetchedAt,
                isFallback: true,
                attribution: provenance.attribution,
                providerAttribution: provenance.providerAttribution,
                expiresAt: provenance.expiresAt
            )
        )
    }
}
