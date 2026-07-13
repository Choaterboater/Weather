import CoreLocation
import Foundation
import WeatherKit

struct WeatherKitPayload: Sendable {
    let current: CurrentWeather
    let hourly: Forecast<HourWeather>
    let daily: Forecast<DayWeather>
    let alerts: [WeatherAlert]
}

struct WeatherKitProvider: WeatherProvider {
    typealias ServiceWorker = @Sendable (
        _ location: CLLocation,
        _ hourlyStartDate: Date,
        _ hourlyEndDate: Date
    ) async throws -> WeatherKitPayload
    typealias Clock = @Sendable () -> Date
    typealias TimeZoneIdentifier = @Sendable (CLLocation) -> String

    private let worker: ServiceWorker
    private let now: Clock
    private let timeZoneIdentifier: TimeZoneIdentifier

    init(
        worker: @escaping ServiceWorker = WeatherKitProvider.liveWeather,
        now: @escaping Clock = { .now },
        // The public WeatherKit request tuple does not expose forecast-zone
        // metadata. Default to the device zone, while keeping this injectable
        // so callers with authoritative location-zone data can supply it.
        timeZoneIdentifier: @escaping TimeZoneIdentifier = { _ in
            TimeZone.autoupdatingCurrent.identifier
        }
    ) {
        self.worker = worker
        self.now = now
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    func forecast(for location: CLLocation) async throws -> WeatherSnapshot {
        let fetchedAt = now()
        let requestWindow = WeatherKitAdapter.requestWindow(now: fetchedAt)
        let zoneIdentifier = timeZoneIdentifier(location)

        do {
            let payload = try await worker(location, requestWindow.start, requestWindow.end)
            let astronomy = WeatherKitAdapter.astronomy(
                for: payload.daily.forecast,
                on: fetchedAt,
                timeZoneIdentifier: zoneIdentifier
            )

            return WeatherSnapshot(
                coordinate: WeatherCoordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                ),
                timeZoneIdentifier: zoneIdentifier,
                current: WeatherKitAdapter.current(payload.current),
                hourly: payload.hourly.forecast.map(WeatherKitAdapter.hourly),
                daily: payload.daily.forecast.map(WeatherKitAdapter.daily),
                alerts: payload.alerts.map(WeatherKitAdapter.alert),
                astronomy: astronomy,
                provenance: WeatherProvenance(
                    source: .weatherKit,
                    fetchedAt: fetchedAt,
                    isFallback: false,
                    attribution: nil
                )
            )
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch let cancellation as URLError where cancellation.code == .cancelled {
            throw cancellation
        } catch {
            throw WeatherKitAdapter.providerError(error)
        }
    }

    private static func liveWeather(
        location: CLLocation,
        hourlyStartDate: Date,
        hourlyEndDate: Date
    ) async throws -> WeatherKitPayload {
        let (current, hourly, daily, alerts) = try await WeatherService.shared.weather(
            for: location,
            including: .current,
            .hourly(startDate: hourlyStartDate, endDate: hourlyEndDate),
            .daily,
            .alerts
        )

        return WeatherKitPayload(
            current: current,
            hourly: hourly,
            daily: daily,
            alerts: alerts ?? []
        )
    }
}

enum WeatherKitAdapter {
    static func fraction(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func celsius(_ measurement: Measurement<UnitTemperature>) -> Double {
        measurement.converted(to: .celsius).value
    }

    static func meters(_ measurement: Measurement<UnitLength>) -> Double {
        measurement.converted(to: .meters).value
    }

    static func millimeters(_ measurement: Measurement<UnitLength>) -> Double {
        measurement.converted(to: .millimeters).value
    }

    static func metersPerSecond(_ measurement: Measurement<UnitSpeed>) -> Double {
        measurement.converted(to: .metersPerSecond).value
    }

    static func hectopascals(_ measurement: Measurement<UnitPressure>) -> Double {
        measurement.converted(to: .hectopascals).value
    }

    static func requestWindow(now: Date) -> DateInterval {
        DateInterval(
            start: now.addingTimeInterval(-6 * 3_600),
            end: now.addingTimeInterval(48 * 3_600)
        )
    }

    static func wind(
        directionDegrees: Double,
        speedMetersPerSecond: Double,
        gustMetersPerSecond: Double?
    ) -> WindSnapshot {
        WindSnapshot(
            directionDegrees: directionDegrees,
            speedMetersPerSecond: speedMetersPerSecond,
            gustMetersPerSecond: gustMetersPerSecond
        )
    }

    static func dailyWind(
        speedMetersPerSecond: Double,
        gustMetersPerSecond: Double?
    ) -> (sustained: Double, peak: Double) {
        (
            sustained: speedMetersPerSecond,
            peak: gustMetersPerSecond ?? speedMetersPerSecond
        )
    }

    static func moonPhaseFraction(_ phase: MoonPhase) -> Double {
        // WeatherKit exposes a category, not an astronomical phase angle.
        // These evenly spaced values are category anchors around one lunar cycle.
        switch phase {
        case .new: 0
        case .waxingCrescent: 0.125
        case .firstQuarter: 0.25
        case .waxingGibbous: 0.375
        case .full: 0.5
        case .waningGibbous: 0.625
        case .lastQuarter: 0.75
        case .waningCrescent: 0.875
        }
    }

    static func providerError(_ error: any Error) -> WeatherProviderError {
        if let providerError = error as? WeatherProviderError {
            return providerError
        }
        if let weatherError = error as? WeatherError {
            switch weatherError {
            case .permissionDenied:
                return .authentication
            case .unknown:
                return .serviceUnavailable
            @unknown default:
                return .serviceUnavailable
            }
        }

        let error = error as NSError
        let description = [
            error.domain,
            error.localizedDescription,
            error.localizedFailureReason,
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let authenticationMarkers = [
            "jwt",
            "authenticat",
            "authoriz",
            "entitlement",
            "listener",
            "permission",
            "token",
        ]

        if authenticationMarkers.contains(where: description.contains) {
            return .authentication
        }
        if error.domain == NSURLErrorDomain {
            return .network(error.localizedDescription)
        }
        return .network(error.localizedDescription)
    }

    static func current(_ weather: CurrentWeather) -> CurrentConditionsSnapshot {
        CurrentConditionsSnapshot(
            date: weather.date,
            temperatureCelsius: celsius(weather.temperature),
            apparentTemperatureCelsius: celsius(weather.apparentTemperature),
            dewPointCelsius: celsius(weather.dewPoint),
            humidityFraction: fraction(weather.humidity),
            pressureHPa: hectopascals(weather.pressure),
            visibilityMeters: meters(weather.visibility),
            uvIndex: weather.uvIndex.value,
            conditionText: weather.condition.description,
            symbolName: weather.symbolName,
            wind: wind(weather.wind)
        )
    }

    static func hourly(_ weather: HourWeather) -> HourlyWeatherPoint {
        HourlyWeatherPoint(
            date: weather.date,
            temperatureCelsius: celsius(weather.temperature),
            apparentTemperatureCelsius: celsius(weather.apparentTemperature),
            dewPointCelsius: celsius(weather.dewPoint),
            humidityFraction: fraction(weather.humidity),
            pressureHPa: hectopascals(weather.pressure),
            visibilityMeters: meters(weather.visibility),
            uvIndex: weather.uvIndex.value,
            cloudCoverFraction: fraction(weather.cloudCover),
            precipitationChance: fraction(weather.precipitationChance),
            precipitationMM: millimeters(weather.precipitationAmount),
            conditionText: weather.condition.description,
            symbolName: weather.symbolName,
            wind: wind(weather.wind)
        )
    }

    static func daily(_ weather: DayWeather) -> DailyWeatherPoint {
        let speed = metersPerSecond(weather.wind.speed)
        let gust = weather.wind.gust.map(metersPerSecond)
        let dailyWind = dailyWind(
            speedMetersPerSecond: speed,
            gustMetersPerSecond: gust
        )
        return DailyWeatherPoint(
            date: weather.date,
            lowCelsius: celsius(weather.lowTemperature),
            highCelsius: celsius(weather.highTemperature),
            precipitationChance: fraction(weather.precipitationChance),
            conditionText: weather.condition.description,
            symbolName: weather.symbolName,
            windMetersPerSecond: dailyWind.sustained,
            windPeakMetersPerSecond: dailyWind.peak,
            astronomy: astronomy(weather)
        )
    }

    static func alert(_ alert: WeatherAlert) -> WeatherAlertSnapshot {
        WeatherAlertSnapshot(
            id: alert.detailsURL.absoluteString,
            summary: alert.summary,
            source: alert.source,
            severity: alert.severity.description,
            startDate: nil,
            endDate: nil,
            detailsURL: alert.detailsURL
        )
    }

    static func astronomy(
        for forecast: [DayWeather],
        on date: Date,
        timeZoneIdentifier: String
    ) -> AstronomySnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent

        guard let today = forecast.first(where: {
            calendar.isDate($0.date, inSameDayAs: date)
        }) else {
            return .empty
        }

        return astronomy(today)
    }

    static func astronomy(_ weather: DayWeather) -> AstronomySnapshot {
        AstronomySnapshot(
            sunrise: weather.sun.sunrise,
            sunset: weather.sun.sunset,
            moonrise: weather.moon.moonrise,
            moonset: weather.moon.moonset,
            // WeatherKit's public MoonEvents surface has no transit instant.
            moonTransit: nil,
            moonPhaseFraction: moonPhaseFraction(weather.moon.phase)
        )
    }

    private static func wind(_ wind: Wind) -> WindSnapshot {
        self.wind(
            directionDegrees: wind.direction.converted(to: .degrees).value,
            speedMetersPerSecond: metersPerSecond(wind.speed),
            gustMetersPerSecond: wind.gust.map(metersPerSecond)
        )
    }
}
