import Foundation
import SwiftUI

/// Condition-driven theming and chart-friendly samples derived from canonical
/// weather snapshots.
enum WeatherTheme {
    /// A two-stop gradient keyed off neutral condition text and SF Symbol name,
    /// so provider-specific enums never leak into the presentation layer.
    static func gradient(
        conditionText: String?,
        symbolName: String?
    ) -> [Color] {
        let condition = "\(conditionText ?? "") \(symbolName ?? "")".lowercased()

        if condition.contains("thunder")
            || condition.contains("storm")
            || condition.contains("bolt") {
            return [Color(red: 0.12, green: 0.14, blue: 0.28), .indigo.opacity(0.4)]
        }
        if condition.contains("snow")
            || condition.contains("flurr")
            || condition.contains("sleet")
            || condition.contains("wintry")
            || condition.contains("freezing") {
            return [Color(red: 0.55, green: 0.68, blue: 0.85), .white.opacity(0.25)]
        }
        if condition.contains("rain")
            || condition.contains("drizzle")
            || condition.contains("shower") {
            return [Color(red: 0.18, green: 0.32, blue: 0.5), .teal.opacity(0.3)]
        }
        if condition.contains("partly")
            || condition.contains("mostly clear")
            || condition.contains("mostly sunny")
            || condition.contains("mostly cloudy")
            || condition.contains("cloud.sun")
            || condition.contains("cloud.moon") {
            return [.blue.opacity(0.55), .gray.opacity(0.25)]
        }
        if condition.contains("fog")
            || condition.contains("haze")
            || condition.contains("smok")
            || condition.contains("cloudy")
            || condition.contains("overcast")
            || condition.contains("cloud") {
            return [.gray.opacity(0.6), .secondary.opacity(0.2)]
        }
        if condition.contains("clear")
            || condition.contains("sunny")
            || condition.contains("hot")
            || condition.contains("sun.max")
            || condition.contains("moon.stars") {
            return [Color(red: 0.20, green: 0.55, blue: 0.95), .cyan.opacity(0.35)]
        }

        return [.blue.opacity(0.35), .cyan.opacity(0.15)]
    }

    /// A dark instrument backdrop for the Weather tab that still shifts with the
    /// sky: the abyss ground with the condition's hue glowing at the top, fading
    /// out toward the bottom.
    @MainActor
    static func skyBackdrop(
        conditionText: String?,
        symbolName: String?
    ) -> some View {
        ZStack {
            Ink.abyss
            LinearGradient(
                colors: [
                    (gradient(
                        conditionText: conditionText,
                        symbolName: symbolName
                    ).first ?? Ink.hull).opacity(0.5),
                    .clear,
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

/// A plottable sample of one hour, decoupled from any weather provider.
struct HourSample: Identifiable {
    /// Use the sample's hour so charts keep identity across body re-evals.
    var id: Date { date }
    let date: Date
    let temperatureCelsius: Double
    let pressureHPa: Double?
    let precipChance: Double
    let windSpeedMph: Double
    let windGustMph: Double?
}

extension Array where Element == HourlyWeatherPoint {
    /// The next `count` hours from now as plottable samples.
    func samples(_ count: Int = 24, now: Date = .now) -> [HourSample] {
        filter { $0.date >= now }
            .prefix(count)
            .map(Self.hourSample(from:))
    }

    /// Full hourly window (including any past hours loaded for pressure trend).
    /// Used for offline snapshots so charts still have a baseline.
    func allSamples() -> [HourSample] {
        map(Self.hourSample(from:))
    }

    private static func hourSample(from hour: HourlyWeatherPoint) -> HourSample {
        HourSample(
            date: hour.date,
            temperatureCelsius: hour.temperatureCelsius,
            pressureHPa: hour.pressureHPa,
            precipChance: hour.precipitationChance ?? 0,
            windSpeedMph: WeatherUnits.milesPerHour(
                metersPerSecond: hour.wind.speedMetersPerSecond
            ),
            windGustMph: hour.wind.gustMetersPerSecond.map {
                WeatherUnits.milesPerHour(metersPerSecond: $0)
            }
        )
    }
}
