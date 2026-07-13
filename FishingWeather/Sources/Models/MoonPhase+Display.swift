import Foundation

/// Provider-neutral lunar phase category derived from cycle position, where
/// `0`/`1` is new moon and `0.5` is full moon.
enum LunarPhase: String, Codable, CaseIterable, Equatable, Sendable {
    case new
    case waxingCrescent
    case firstQuarter
    case waxingGibbous
    case full
    case waningGibbous
    case lastQuarter
    case waningCrescent
    case unknown

    init(cycleFraction: Double?) {
        guard let cycleFraction, cycleFraction.isFinite else {
            self = .unknown
            return
        }

        var normalized = cycleFraction.truncatingRemainder(dividingBy: 1)
        if normalized < 0 { normalized += 1 }
        let index = Int(floor(normalized * 8 + 0.5)) % 8
        self = [
            .new,
            .waxingCrescent,
            .firstQuarter,
            .waxingGibbous,
            .full,
            .waningGibbous,
            .lastQuarter,
            .waningCrescent,
        ][index]
    }

    var displayName: String {
        switch self {
        case .new: "New Moon"
        case .waxingCrescent: "Waxing Crescent"
        case .firstQuarter: "First Quarter"
        case .waxingGibbous: "Waxing Gibbous"
        case .full: "Full Moon"
        case .waningGibbous: "Waning Gibbous"
        case .lastQuarter: "Last Quarter"
        case .waningCrescent: "Waning Crescent"
        case .unknown: "Moon"
        }
    }

    var symbolName: String {
        switch self {
        case .new: "moonphase.new.moon"
        case .waxingCrescent: "moonphase.waxing.crescent"
        case .firstQuarter: "moonphase.first.quarter"
        case .waxingGibbous: "moonphase.waxing.gibbous"
        case .full: "moonphase.full.moon"
        case .waningGibbous: "moonphase.waning.gibbous"
        case .lastQuarter: "moonphase.last.quarter"
        case .waningCrescent: "moonphase.waning.crescent"
        case .unknown: "moon"
        }
    }

    var biteRating: String {
        switch self {
        case .new, .full: "Strong"
        case .firstQuarter, .lastQuarter: "Weak"
        case .waxingCrescent, .waxingGibbous, .waningGibbous, .waningCrescent, .unknown:
            "Moderate"
        }
    }

    /// Approximate illuminated fraction retained from the prior WeatherKit
    /// category presentation (0 = dark, 1 = fully illuminated).
    var illuminationFraction: Double {
        switch self {
        case .new: 0
        case .waxingCrescent, .waningCrescent: 0.25
        case .firstQuarter, .lastQuarter, .unknown: 0.5
        case .waxingGibbous, .waningGibbous: 0.75
        case .full: 1
        }
    }
}
