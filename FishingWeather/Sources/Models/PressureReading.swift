import Foundation

/// Direction the barometric pressure is moving — what matters most to the bite.
enum PressureTendency: Equatable, Sendable {
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

    var fishingNote: String {
        switch self {
        case .falling: "Falling pressure often turns on the bite — fish ahead of the front."
        case .rising: "Rising pressure after a front can slow things down. Fish deeper and slower."
        case .steady: "Stable pressure means steady, predictable fishing."
        }
    }
}

/// Current pressure plus its short-term trend. Pressure stays nil when a
/// provider does not report it; neither UI nor scoring fabricates a value.
struct PressureReading: Sendable {
    let pressure: Measurement<UnitPressure>?
    let tendency: PressureTendency
    let changePerHour: Double?

    private static let minimumBaselineAge: TimeInterval = 3_600

    static func analyze(
        currentHPa: Double?,
        hourly: [HourlyWeatherPoint],
        now: Date
    ) -> PressureReading {
        analyze(
            nowHPa: currentHPa,
            history: hourly.compactMap { point in
                point.pressureHPa.map { (date: point.date, hPa: $0) }
            },
            now: now,
            fallback: .steady
        )
    }

    /// The pressure to attribute to `date`. A forecast value for that exact
    /// hour always wins. An observed reading is carried onto an hour only when
    /// it genuinely covers it, so a single current observation can never
    /// masquerade as tomorrow's forecast pressure.
    static func pressure(
        at date: Date,
        forecastHPa: Double?,
        samples: [(date: Date, hPa: Double)],
        maximumCarry: TimeInterval = 3_600
    ) -> Double? {
        if let forecastHPa, forecastHPa.isFinite { return forecastHPa }
        let nearest = samples
            .filter { $0.hPa.isFinite && $0.date.timeIntervalSinceReferenceDate.isFinite }
            .min {
                abs($0.date.timeIntervalSince(date))
                    < abs($1.date.timeIntervalSince(date))
            }
        guard let nearest,
              abs(nearest.date.timeIntervalSince(date)) <= maximumCarry
        else { return nil }
        return nearest.hPa
    }

    static func analyze(
        nowHPa: Double?,
        history: [(date: Date, hPa: Double)],
        now: Date,
        fallback: PressureTendency
    ) -> PressureReading {
        guard let nowHPa, nowHPa.isFinite else {
            return PressureReading(
                pressure: nil,
                tendency: .steady,
                changePerHour: nil
            )
        }

        let pressure = Measurement(
            value: nowHPa,
            unit: UnitPressure.hectopascals
        )
        let target = now.addingTimeInterval(-3 * 3_600)
        let past = history
            .filter {
                $0.hPa.isFinite
                    && now.timeIntervalSince($0.date) >= minimumBaselineAge
            }
            .min {
                abs($0.date.timeIntervalSince(target))
                    < abs($1.date.timeIntervalSince(target))
            }

        guard let past else {
            return PressureReading(
                pressure: pressure,
                tendency: fallback,
                changePerHour: nil
            )
        }

        let hours = now.timeIntervalSince(past.date) / 3_600
        let perHour = (nowHPa - past.hPa) / hours
        let tendency: PressureTendency =
            perHour > 0.3 ? .rising : (perHour < -0.3 ? .falling : .steady)
        return PressureReading(
            pressure: pressure,
            tendency: tendency,
            changePerHour: perHour
        )
    }
}
