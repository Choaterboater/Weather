import Foundation
import WeatherKit

/// Direction the barometric pressure is moving — what matters most to the bite.
enum PressureTendency {
    case rising, falling, steady

    var label: String {
        switch self {
        case .rising: "Rising"
        case .falling: "Falling"
        case .steady: "Steady"
        }
    }

    var symbolName: String {
        switch self {
        case .rising: "arrow.up.right"
        case .falling: "arrow.down.right"
        case .steady: "arrow.right"
        }
    }

    /// Plain-language interpretation. These are fishing rules of thumb, not AI.
    var fishingNote: String {
        switch self {
        case .falling: "Falling pressure often turns on the bite — fish ahead of the front."
        case .rising: "Rising pressure after a front can slow things down. Fish deeper and slower."
        case .steady: "Stable pressure means steady, predictable fishing."
        }
    }
}

/// Current pressure plus the short-term trend, computed from the hourly history
/// when available and otherwise from WeatherKit's own trend value.
struct PressureReading {
    let pressure: Measurement<UnitPressure>
    let tendency: PressureTendency
    /// Change in hectopascals per hour over the comparison window, if computed.
    let changePerHour: Double?

    /// A baseline younger than this can't support a slope: the current hour's
    /// forecast entry may be only minutes old, and dividing a forecast-vs-
    /// observation mismatch by minutes reads as a huge, spurious trend.
    private static let minimumBaselineAge: TimeInterval = 3600

    static func analyze(current: CurrentWeather, hourly: [HourWeather], now: Date) -> PressureReading {
        let fallback: PressureTendency = switch current.pressureTrend {
        case .rising: .rising
        case .falling: .falling
        default: .steady
        }
        return analyze(
            nowHPa: current.pressure.converted(to: .hectopascals).value,
            history: hourly.map { (date: $0.date, hPa: $0.pressure.converted(to: .hectopascals).value) },
            now: now,
            fallback: fallback
        )
    }

    /// Pure core — WeatherKit's types have no public initializers, so tests
    /// (and any future widget) drive this overload directly.
    static func analyze(
        nowHPa: Double,
        history: [(date: Date, hPa: Double)],
        now: Date,
        fallback: PressureTendency
    ) -> PressureReading {
        let pressure = Measurement(value: nowHPa, unit: UnitPressure.hectopascals)
        let target = now.addingTimeInterval(-3 * 3600)

        // Nearest sample to ~3h ago that's old enough to be a real baseline.
        let past = history
            .filter { now.timeIntervalSince($0.date) >= minimumBaselineAge }
            .min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }

        guard let past else {
            return PressureReading(pressure: pressure, tendency: fallback, changePerHour: nil)
        }

        let hours = now.timeIntervalSince(past.date) / 3600
        let perHour = (nowHPa - past.hPa) / hours
        let tendency: PressureTendency =
            perHour > 0.3 ? .rising : (perHour < -0.3 ? .falling : .steady)
        return PressureReading(pressure: pressure, tendency: tendency, changePerHour: perHour)
    }
}
