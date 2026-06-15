import WeatherKit

extension MoonPhase {
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
        @unknown default: "Moon"
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
        @unknown default: "moon"
        }
    }

    /// New and full moons produce the strongest solunar feeding periods.
    var biteRating: String {
        switch self {
        case .new, .full: "Strong"
        case .firstQuarter, .lastQuarter: "Weak"
        default: "Moderate"
        }
    }
}
