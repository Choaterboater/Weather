import SwiftUI
import WeatherKit

/// Condition-driven theming and chart-friendly samples derived from WeatherKit's
/// opaque `Forecast` types.
enum WeatherTheme {
    /// A two-stop gradient keyed off the WeatherKit condition, so the app's
    /// backgrounds shift with the sky.
    static func gradient(for condition: WeatherCondition?) -> [Color] {
        switch condition {
        case .clear, .mostlyClear, .hot:
            [Color(red: 0.20, green: 0.55, blue: 0.95), .cyan.opacity(0.35)]
        case .partlyCloudy, .mostlyCloudy:
            [.blue.opacity(0.55), .gray.opacity(0.25)]
        case .cloudy, .foggy, .haze, .smoky:
            [.gray.opacity(0.6), .secondary.opacity(0.2)]
        case .drizzle, .rain, .heavyRain, .sunShowers:
            [Color(red: 0.18, green: 0.32, blue: 0.5), .teal.opacity(0.3)]
        case .thunderstorms, .strongStorms, .isolatedThunderstorms, .scatteredThunderstorms:
            [Color(red: 0.12, green: 0.14, blue: 0.28), .indigo.opacity(0.4)]
        case .snow, .flurries, .sleet, .wintryMix, .blizzard, .freezingRain, .freezingDrizzle:
            [Color(red: 0.55, green: 0.68, blue: 0.85), .white.opacity(0.25)]
        default:
            [.blue.opacity(0.35), .cyan.opacity(0.15)]
        }
    }
}

/// A plottable sample of one hour, decoupled from WeatherKit's `Forecast`.
struct HourSample: Identifiable {
    let id = UUID()
    let date: Date
    let temperature: Double   // °F
    let pressureHPa: Double
    let precipChance: Double
}

extension Forecast where Element == HourWeather {
    /// The next `count` hours from now as plottable samples.
    func samples(_ count: Int = 24, now: Date = .now) -> [HourSample] {
        forecast
            .filter { $0.date >= now }
            .prefix(count)
            .map {
                HourSample(
                    date: $0.date,
                    temperature: $0.temperature.converted(to: .fahrenheit).value,
                    pressureHPa: $0.pressure.converted(to: .hectopascals).value,
                    precipChance: $0.precipitationChance
                )
            }
    }
}

extension MoonPhase {
    /// Approximate illuminated fraction (0 = new, 1 = full) for a tidy gauge,
    /// since WeatherKit reports a named phase rather than a lit fraction.
    var illuminationFraction: Double {
        switch self {
        case .new: 0.0
        case .waxingCrescent, .waningCrescent: 0.25
        case .firstQuarter, .lastQuarter: 0.5
        case .waxingGibbous, .waningGibbous: 0.75
        case .full: 1.0
        @unknown default: 0.5
        }
    }
}
