import CoreLocation
import Foundation

struct NWSWeatherProvider: WeatherProvider {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias AstronomyWorker = @Sendable (
        CLLocation,
        Date,
        Calendar
    ) -> AstronomySnapshot

    private let loader: Loader
    private let userAgent: String
    private let astronomy: AstronomyWorker

    init(
        loader: @escaping Loader = NWSWeatherProvider.liveLoad,
        userAgent: String = AppIdentity.userAgent,
        astronomy: @escaping AstronomyWorker = { _, _, _ in .empty }
    ) {
        self.loader = loader
        self.userAgent = userAgent
        self.astronomy = astronomy
    }

    func forecast(for location: CLLocation) async throws -> WeatherSnapshot {
        do {
            let fetchedAt = Date.now
            let point = try await loadPoint(location)
            let calendar: Calendar = {
                var value = Calendar(identifier: .gregorian)
                value.timeZone = TimeZone(identifier: point.properties.timeZone) ?? .gmt
                return value
            }()

            var hourlyValue: [HourlyWeatherPoint]?
            var dailyValue: [DailyWeatherPoint]?
            var observationValue: NWSObservationProperties?
            var alertValue: [WeatherAlertSnapshot]?

            try await withThrowingTaskGroup(of: NWSFetchResult.self) { group in
                group.addTask {
                    .hourly(try await self.loadHourly(point.properties.forecastHourly))
                }
                group.addTask {
                    .daily(try await self.loadDaily(
                        point.properties.forecast,
                        location: location,
                        calendar: calendar
                    ))
                }
                group.addTask {
                    .observation(try await self.loadObservation(
                        point.properties.observationStations
                    ))
                }
                group.addTask {
                    .alerts(try await self.loadAlerts(location))
                }

                do {
                    while let result = try await group.next() {
                        switch result {
                        case let .hourly(value): hourlyValue = value
                        case let .daily(value): dailyValue = value
                        case let .observation(value): observationValue = value
                        case let .alerts(value): alertValue = value
                        }
                    }
                } catch {
                    group.cancelAll()
                    throw error
                }
            }

            guard let hourlyValue,
                  let dailyValue,
                  let alertValue,
                  let firstHour = hourlyValue.first
            else {
                throw WeatherProviderError.decoding("NWS hourly forecast contained no periods")
            }

            return WeatherSnapshot(
                coordinate: WeatherCoordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                ),
                timeZoneIdentifier: point.properties.timeZone,
                current: current(observationValue, fallback: firstHour),
                hourly: hourlyValue,
                daily: dailyValue,
                alerts: alertValue,
                astronomy: astronomy(location, fetchedAt, calendar),
                provenance: WeatherProvenance(
                    source: .nws,
                    fetchedAt: fetchedAt,
                    isFallback: false,
                    attribution: "National Weather Service"
                )
            )
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch let cancellation as URLError where cancellation.code == .cancelled {
            throw cancellation
        } catch let error as WeatherProviderError {
            throw error
        } catch let error as DecodingError {
            throw WeatherProviderError.decoding(error.localizedDescription)
        } catch let error as URLError {
            throw WeatherProviderError.from(error)
        } catch {
            throw WeatherProviderError.from(error)
        }
    }

    private func loadPoint(_ location: CLLocation) async throws -> NWSPointResponse {
        let coordinate = Self.coordinateString(location)
        guard let url = URL(string: "https://api.weather.gov/points/\(coordinate)") else {
            throw WeatherProviderError.unsupportedRegion
        }
        let data = try await data(for: url, notFound: .unsupportedRegion)
        return try decode(NWSPointResponse.self, from: data)
    }

    private func loadHourly(_ url: URL) async throws -> [HourlyWeatherPoint] {
        let data = try await data(for: url, notFound: .serviceUnavailable)
        let response = try decode(
            NWSForecastResponse.self,
            from: data
        )

        return try response.properties.periods.map(Self.hourly)
    }

    private func loadDaily(
        _ url: URL,
        location: CLLocation,
        calendar: Calendar
    ) async throws -> [DailyWeatherPoint] {
        let data = try await data(for: url, notFound: .serviceUnavailable)
        let response = try decode(
            NWSDailyForecastResponse.self,
            from: data
        )
        return try Self.daily(
            response.properties.periods,
            calendar: calendar,
            astronomy: { date in
                astronomy(location, date, calendar)
            }
        )
    }

    private func loadObservation(_ stationsURL: URL) async throws -> NWSObservationProperties? {
        guard let stationData = try await optionalData(for: stationsURL),
              let stationURL = try decode(NWSStationCollection.self, from: stationData)
                .features.first?.id
        else { return nil }

        let latestURL = stationURL.appending(path: "observations/latest")
        guard let observationData = try await optionalData(for: latestURL) else { return nil }
        return try decode(NWSObservationResponse.self, from: observationData).properties
    }

    private func loadAlerts(_ location: CLLocation) async throws -> [WeatherAlertSnapshot] {
        var components = URLComponents(string: "https://api.weather.gov/alerts/active")
        components?.queryItems = [
            URLQueryItem(name: "point", value: Self.coordinateString(location)),
        ]
        guard let url = components?.url else {
            throw WeatherProviderError.unsupportedRegion
        }

        let data = try await data(for: url, notFound: .serviceUnavailable)
        let response = try decode(
            NWSAlertCollection.self,
            from: data
        )
        return response.features.map(Self.alert)
    }

    private func data(
        for url: URL,
        notFound: WeatherProviderError
    ) async throws -> Data {
        guard let data = try await requestData(for: url, notFound: notFound) else {
            throw notFound
        }
        return data
    }

    private func optionalData(for url: URL) async throws -> Data? {
        try await requestData(for: url, notFound: nil)
    }

    private func requestData(
        for url: URL,
        notFound: WeatherProviderError?
    ) async throws -> Data? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await loader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherProviderError.serviceUnavailable
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return data
        case 404:
            if let notFound {
                throw notFound
            }
            return nil
        case 429:
            throw WeatherProviderError.rateLimited(
                retryAfter: Self.retryAfter(httpResponse.value(forHTTPHeaderField: "Retry-After"))
            )
        case 500..<600:
            throw WeatherProviderError.serviceUnavailable
        default:
            throw WeatherProviderError.serviceUnavailable
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            throw WeatherProviderError.decoding(error.localizedDescription)
        }
    }

    private func current(
        _ observation: NWSObservationProperties?,
        fallback: HourlyWeatherPoint
    ) -> CurrentConditionsSnapshot {
        let temperature = observation.flatMap { Self.temperature($0.temperature) }
            ?? fallback.temperatureCelsius
        let conditionText = observation.flatMap { $0.textDescription.nonEmpty }
            ?? fallback.conditionText
        let direction = observation.flatMap { Self.directionDegrees($0.windDirection) }
            ?? fallback.wind.directionDegrees
        let speed = observation.flatMap { Self.speedMetersPerSecond($0.windSpeed) }
            ?? fallback.wind.speedMetersPerSecond
        let symbolName = observation
            .flatMap { $0.icon.nonEmpty }
            .map { Self.symbol(text: conditionText, icon: $0) }
            ?? fallback.symbolName

        return CurrentConditionsSnapshot(
            date: observation.flatMap { Self.date($0.timestamp) } ?? fallback.date,
            temperatureCelsius: temperature,
            apparentTemperatureCelsius: observation.flatMap { Self.temperature($0.heatIndex) }
                ?? observation.flatMap { Self.temperature($0.windChill) }
                ?? temperature,
            dewPointCelsius: observation.flatMap { Self.temperature($0.dewpoint) }
                ?? fallback.dewPointCelsius,
            humidityFraction: observation.flatMap { Self.fraction($0.relativeHumidity) }
                ?? fallback.humidityFraction,
            pressureHPa: observation.flatMap { Self.hectopascals($0.barometricPressure) },
            visibilityMeters: observation.flatMap { Self.meters($0.visibility) },
            uvIndex: fallback.uvIndex,
            conditionText: conditionText,
            symbolName: symbolName,
            wind: WindSnapshot(
                directionDegrees: direction,
                speedMetersPerSecond: speed,
                gustMetersPerSecond: observation.flatMap {
                    Self.speedMetersPerSecond($0.windGust)
                }
            )
        )
    }

    private static func hourly(_ period: NWSForecastPeriod) throws -> HourlyWeatherPoint {
        guard let parsedDate = date(period.startTime),
              let temperatureCelsius = celsius(period.temperature, unit: period.temperatureUnit),
              let wind = windRange(period.windSpeed),
              let direction = compassDegrees(
                  period.windDirection,
                  permitsVariable: wind.upperMetersPerSecond == 0
              )
        else {
            throw WeatherProviderError.decoding("NWS hourly period used an unsupported value")
        }

        return HourlyWeatherPoint(
            date: parsedDate,
            temperatureCelsius: temperatureCelsius,
            apparentTemperatureCelsius: nil,
            dewPointCelsius: temperature(period.dewpoint),
            humidityFraction: fraction(period.relativeHumidity),
            pressureHPa: nil,
            visibilityMeters: nil,
            uvIndex: nil,
            cloudCoverFraction: nil,
            precipitationChance: fraction(period.probabilityOfPrecipitation),
            precipitationMM: nil,
            conditionText: period.shortForecast,
            symbolName: symbol(text: period.shortForecast, icon: period.icon),
            wind: WindSnapshot(
                directionDegrees: direction,
                speedMetersPerSecond: wind.midpointMetersPerSecond,
                gustMetersPerSecond: nil
            )
        )
    }

    private static func daily(
        _ periods: [NWSDailyPeriod],
        calendar: Calendar,
        astronomy: (Date) -> AstronomySnapshot
    ) throws -> [DailyWeatherPoint] {
        let candidates = try periods.map { period -> NWSDailyCandidate in
            guard let parsedDate = date(period.startTime),
                  let temperatureCelsius = celsius(
                      period.temperature,
                      unit: period.temperatureUnit
                  ),
                  let wind = windRange(period.windSpeed),
                  compassDegrees(
                      period.windDirection,
                      permitsVariable: wind.upperMetersPerSecond == 0
                  ) != nil
            else {
                throw WeatherProviderError.decoding("NWS daily period used an unsupported value")
            }
            return NWSDailyCandidate(
                date: calendar.startOfDay(for: parsedDate),
                isDaytime: period.isDaytime,
                temperatureCelsius: temperatureCelsius,
                precipitationChance: fraction(period.probabilityOfPrecipitation),
                conditionText: period.shortForecast,
                symbolName: symbol(text: period.shortForecast, icon: period.icon),
                windMetersPerSecond: wind.midpointMetersPerSecond,
                windPeakMetersPerSecond: wind.upperMetersPerSecond
            )
        }

        let groups = Dictionary(grouping: candidates, by: \.date)
        return groups
            .keys
            .sorted()
            .compactMap { date in
                guard let group = groups[date],
                      let daytime = group.first(where: \.isDaytime),
                      let nighttime = group.first(where: { !$0.isDaytime })
                else { return nil }

                return DailyWeatherPoint(
                    date: date,
                    lowCelsius: nighttime.temperatureCelsius,
                    highCelsius: daytime.temperatureCelsius,
                    precipitationChance: group.compactMap(\.precipitationChance).max(),
                    conditionText: daytime.conditionText,
                    symbolName: daytime.symbolName,
                    windMetersPerSecond: group.compactMap(\.windMetersPerSecond).max(),
                    windPeakMetersPerSecond: group.compactMap(\.windPeakMetersPerSecond).max(),
                    astronomy: astronomy(date)
                )
            }
    }

    private static func alert(_ feature: NWSAlertFeature) -> WeatherAlertSnapshot {
        let properties = feature.properties
        let detailsURL = validHTTPURL(properties.detailsIdentifier) ?? validHTTPURL(feature.id)
        let identifier = properties.id.nonEmpty
            ?? feature.id.nonEmpty
            ?? properties.detailsIdentifier.nonEmpty
            ?? [Optional(properties.event), properties.effective ?? properties.onset]
                .compactMap(\.nonEmpty)
                .joined(separator: "|")

        return WeatherAlertSnapshot(
            id: identifier,
            summary: properties.headline.nonEmpty ?? properties.event,
            source: properties.senderName,
            severity: properties.severity,
            startDate: date(properties.onset) ?? date(properties.effective),
            endDate: date(properties.ends) ?? date(properties.expires),
            detailsURL: detailsURL
        )
    }

    private static func coordinateString(_ location: CLLocation) -> String {
        ExternalRequestPrivacy.coordinateString(location, decimalPlaces: 3)
    }

    private static func celsius(_ value: Double, unit: String) -> Double? {
        switch unit.uppercased() {
        case "F": (value - 32) * 5 / 9
        case "C": value
        default: nil
        }
    }

    private static func temperature(_ value: NWSQuantitativeValue?) -> Double? {
        guard let measurement = value,
              let value = measurement.value,
              let unit = measurement.unitCode?.lowercased()
        else { return nil }
        if unit.contains("degf") { return (value - 32) * 5 / 9 }
        if unit.contains("degc") { return value }
        if unit.hasSuffix(":k") || unit == "k" { return value - 273.15 }
        return nil
    }

    private static func fraction(_ measurement: NWSQuantitativeValue?) -> Double? {
        guard let measurement,
              let value = measurement.value,
              measurement.unitCode?.lowercased().contains("percent") == true
        else { return nil }
        return min(max(value / 100, 0), 1)
    }

    private static func hectopascals(_ measurement: NWSQuantitativeValue?) -> Double? {
        guard let measurement,
              let value = measurement.value,
              let unit = measurement.unitCode?.lowercased()
        else { return nil }
        if unit.hasSuffix(":pa") || unit == "pa" { return value / 100 }
        return nil
    }

    private static func meters(_ measurement: NWSQuantitativeValue?) -> Double? {
        guard let measurement,
              let value = measurement.value,
              let unit = measurement.unitCode?.lowercased()
        else { return nil }
        if unit.hasSuffix(":m") || unit == "m" { return value }
        return nil
    }

    private static func speedMetersPerSecond(_ measurement: NWSQuantitativeValue?) -> Double? {
        guard let measurement,
              let value = measurement.value,
              let unit = measurement.unitCode?.lowercased()
        else { return nil }
        if unit.contains("km_h") || unit.contains("km/h") { return value / 3.6 }
        return nil
    }

    private static func directionDegrees(_ measurement: NWSQuantitativeValue?) -> Double? {
        guard let measurement,
              let value = measurement.value,
              measurement.unitCode?.lowercased().contains("degree") == true
        else { return nil }
        let normalized = value.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }

    private static func compassDegrees(
        _ direction: String,
        permitsVariable: Bool
    ) -> Double? {
        let values: [String: Double] = [
            "N": 0, "NNE": 22.5, "NE": 45, "ENE": 67.5,
            "E": 90, "ESE": 112.5, "SE": 135, "SSE": 157.5,
            "S": 180, "SSW": 202.5, "SW": 225, "WSW": 247.5,
            "W": 270, "WNW": 292.5, "NW": 315, "NNW": 337.5,
        ]
        let normalized = direction.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let value = values[normalized] { return value }
        if permitsVariable, normalized.isEmpty || normalized == "CALM" || normalized == "VRB" {
            return 0
        }
        return nil
    }

    private static func windRange(_ text: String) -> NWSWindRange? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "calm" {
            return NWSWindRange(midpointMetersPerSecond: 0, upperMetersPerSecond: 0)
        }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace)
        let first: Double
        let upper: Double

        switch tokens.count {
        case 2:
            guard tokens[1].lowercased() == "mph",
                  let speed = Double(tokens[0]),
                  speed.isFinite,
                  speed >= 0
            else { return nil }
            first = speed
            upper = speed
        case 4:
            guard tokens[1].lowercased() == "to",
                  tokens[3].lowercased() == "mph",
                  let lowerSpeed = Double(tokens[0]),
                  let upperSpeed = Double(tokens[2]),
                  lowerSpeed.isFinite,
                  upperSpeed.isFinite,
                  lowerSpeed >= 0,
                  upperSpeed >= lowerSpeed
            else { return nil }
            first = lowerSpeed
            upper = upperSpeed
        default:
            return nil
        }

        let factor = 0.44704

        return NWSWindRange(
            midpointMetersPerSecond: ((first + upper) / 2) * factor,
            upperMetersPerSecond: upper * factor
        )
    }

    private static func symbol(text: String, icon: String?) -> String {
        let category = "\(text) \(icon ?? "")".lowercased()
        let isNight = category.contains("/night/")

        if category.contains("thunder") || category.contains("tsra") {
            return "cloud.bolt.rain"
        }
        if category.contains("snow") || category.contains("blizzard") {
            return "snow"
        }
        if category.contains("sleet") || category.contains("freezing") || category.contains("ice") {
            return "cloud.sleet"
        }
        if category.contains("rain") || category.contains("shower") || category.contains("drizzle") {
            return "cloud.rain"
        }
        if category.contains("fog") || category.contains("mist") || category.contains("haze") {
            return "cloud.fog"
        }
        if category.contains("partly") || category.contains("mostly sunny")
            || category.contains("scattered") || category.contains("sct")
        {
            return isNight ? "cloud.moon" : "cloud.sun"
        }
        if category.contains("sunny") || category.contains("clear") || category.contains("skc") {
            return isNight ? "moon.stars" : "sun.max"
        }
        if category.contains("wind") {
            return "wind"
        }
        return "cloud"
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    private static func validHTTPURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil
        else { return nil }
        return url
    }

    private static func retryAfter(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value) { return max(0, seconds) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }

    private static func liveLoad(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

private struct NWSPointResponse: Decodable, Sendable {
    let properties: Properties

    struct Properties: Decodable, Sendable {
        let forecast: URL
        let forecastHourly: URL
        let observationStations: URL
        let timeZone: String
    }
}

private struct NWSForecastResponse: Decodable, Sendable {
    let properties: Properties

    struct Properties: Decodable, Sendable {
        let periods: [NWSForecastPeriod]
    }
}

private struct NWSDailyForecastResponse: Decodable, Sendable {
    let properties: Properties

    struct Properties: Decodable, Sendable {
        let periods: [NWSDailyPeriod]
    }
}

private struct NWSForecastPeriod: Decodable, Sendable {
    let startTime: String
    let temperature: Double
    let temperatureUnit: String
    let probabilityOfPrecipitation: NWSQuantitativeValue?
    let dewpoint: NWSQuantitativeValue?
    let relativeHumidity: NWSQuantitativeValue?
    let windSpeed: String
    let windDirection: String
    let icon: String?
    let shortForecast: String
}

private struct NWSDailyPeriod: Decodable, Sendable {
    let startTime: String
    let isDaytime: Bool
    let temperature: Double
    let temperatureUnit: String
    let probabilityOfPrecipitation: NWSQuantitativeValue?
    let windSpeed: String
    let windDirection: String
    let icon: String?
    let shortForecast: String
}

private struct NWSStationCollection: Decodable, Sendable {
    let features: [Feature]

    struct Feature: Decodable, Sendable {
        let id: URL
    }
}

private struct NWSObservationResponse: Decodable, Sendable {
    let properties: NWSObservationProperties
}

private struct NWSObservationProperties: Decodable, Sendable {
    let timestamp: String?
    let textDescription: String?
    let icon: String?
    let temperature: NWSQuantitativeValue?
    let dewpoint: NWSQuantitativeValue?
    let windChill: NWSQuantitativeValue?
    let heatIndex: NWSQuantitativeValue?
    let windDirection: NWSQuantitativeValue?
    let windSpeed: NWSQuantitativeValue?
    let windGust: NWSQuantitativeValue?
    let barometricPressure: NWSQuantitativeValue?
    let visibility: NWSQuantitativeValue?
    let relativeHumidity: NWSQuantitativeValue?
}

private struct NWSQuantitativeValue: Decodable, Sendable {
    let unitCode: String?
    let value: Double?
}

private struct NWSAlertCollection: Decodable, Sendable {
    let features: [NWSAlertFeature]
}

private struct NWSAlertFeature: Decodable, Sendable {
    let id: String?
    let properties: Properties

    struct Properties: Decodable, Sendable {
        let id: String?
        let detailsIdentifier: String?
        let event: String
        let headline: String?
        let senderName: String
        let severity: String?
        let effective: String?
        let onset: String?
        let ends: String?
        let expires: String?

        enum CodingKeys: String, CodingKey {
            case id
            case detailsIdentifier = "@id"
            case event
            case headline
            case senderName
            case severity
            case effective
            case onset
            case ends
            case expires
        }
    }
}

private enum NWSFetchResult: Sendable {
    case hourly([HourlyWeatherPoint])
    case daily([DailyWeatherPoint])
    case observation(NWSObservationProperties?)
    case alerts([WeatherAlertSnapshot])
}

private struct NWSWindRange: Sendable {
    let midpointMetersPerSecond: Double
    let upperMetersPerSecond: Double
}

private struct NWSDailyCandidate: Sendable {
    let date: Date
    let isDaytime: Bool
    let temperatureCelsius: Double
    let precipitationChance: Double?
    let conditionText: String
    let symbolName: String
    let windMetersPerSecond: Double?
    let windPeakMetersPerSecond: Double?
}

private extension String {
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        self?.nonEmpty
    }
}
