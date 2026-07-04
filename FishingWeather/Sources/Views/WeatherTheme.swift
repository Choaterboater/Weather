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

    /// A dark instrument backdrop for the Weather tab that still shifts with the
    /// sky: the abyss ground with the condition's hue glowing at the top, fading
    /// out toward the bottom.
    @MainActor
    static func skyBackdrop(for condition: WeatherCondition?) -> some View {
        ZStack {
            Ink.abyss
            LinearGradient(
                colors: [(gradient(for: condition).first ?? Ink.hull).opacity(0.5), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

/// A plottable sample of one hour, decoupled from WeatherKit's `Forecast`.
/// Wind fields default so older call sites and offline snapshots that predate
/// wind still construct cleanly (they read back as calm rather than failing).
struct HourSample: Identifiable {
    /// Use the sample's hour so charts keep identity across body re-evals.
    var id: Date { date }
    let date: Date
    let temperature: Double   // °F
    let pressureHPa: Double
    let precipChance: Double
    var windSpeedMph: Double = 0
    var windGustMph: Double? = nil
}

extension Forecast where Element == HourWeather {
    /// The next `count` hours from now as plottable samples.
    func samples(_ count: Int = 24, now: Date = .now) -> [HourSample] {
        forecast
            .filter { $0.date >= now }
            .prefix(count)
            .map(Self.hourSample(from:))
    }

    /// Full hourly window (including any past hours loaded for pressure trend).
    /// Used for offline snapshots so charts still have a baseline.
    func allSamples() -> [HourSample] {
        forecast.map(Self.hourSample(from:))
    }

    private static func hourSample(from hour: HourWeather) -> HourSample {
        HourSample(
            date: hour.date,
            temperature: hour.temperature.converted(to: .fahrenheit).value,
            pressureHPa: hour.pressure.converted(to: .hectopascals).value,
            precipChance: hour.precipitationChance,
            windSpeedMph: hour.wind.speed.converted(to: .milesPerHour).value,
            windGustMph: hour.wind.gust?.converted(to: .milesPerHour).value
        )
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
