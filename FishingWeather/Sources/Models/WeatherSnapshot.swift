import Foundation

enum WeatherSource: String, Codable, Sendable {
    case weatherKit
    case nws
    case cache
}

struct WeatherProvenance: Codable, Equatable, Sendable {
    let source: WeatherSource
    let fetchedAt: Date
    let isFallback: Bool
    let attribution: String?
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
                attribution: provenance.attribution
            )
        )
    }
}
