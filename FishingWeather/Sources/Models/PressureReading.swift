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

    static func analyze(current: CurrentWeather, hourly: [HourWeather], now: Date) -> PressureReading {
        let nowPressure = current.pressure
        let target = now.addingTimeInterval(-3 * 3600)

        // Nearest past hour to ~3h ago that WeatherKit gives us.
        let past = hourly
            .filter { $0.date < now }
            .min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }

        if let past {
            let hours = now.timeIntervalSince(past.date) / 3600
            let deltaHPa = nowPressure.converted(to: .hectopascals).value
                - past.pressure.converted(to: .hectopascals).value
            let perHour = hours > 0 ? deltaHPa / hours : 0
            let tendency: PressureTendency =
                perHour > 0.3 ? .rising : (perHour < -0.3 ? .falling : .steady)
            return PressureReading(pressure: nowPressure, tendency: tendency, changePerHour: perHour)
        }

        // No usable history — fall back to WeatherKit's reported trend.
        let tendency: PressureTendency
        switch current.pressureTrend {
        case .rising: tendency = .rising
        case .falling: tendency = .falling
        default: tendency = .steady
        }
        return PressureReading(pressure: nowPressure, tendency: tendency, changePerHour: nil)
    }
}
