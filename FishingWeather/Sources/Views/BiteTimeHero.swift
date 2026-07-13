import SwiftUI

/// The glanceable decision at the top of BiteTime. It consumes the exact
/// provider hour selected by Timeline and Pro Forecast, so its score and
/// weather facts cannot drift from the detailed surfaces below it.
struct BiteTimeHero: View {
    let point: ForecastPoint
    let species: Species
    let timeZone: TimeZone
    let isCurrentHour: Bool
    let window: BiteWindow?

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var score: Int? {
        point.biteScore.flatMap { BiteScoreBand.band(for: $0) == nil ? nil : $0 }
    }

    private var band: BiteScoreBand? {
        score.flatMap(BiteScoreBand.band(for:))
    }

    private var temperature: String {
        WeatherUnits.wholeTemperature(
            celsius: point.weather.temperatureCelsius,
            locale: locale
        )
    }

    private var wind: String {
        let speed = WeatherUnits.milesPerHour(
            metersPerSecond: point.weather.wind.speedMetersPerSecond
        )
        guard speed.isFinite else { return "Unavailable" }
        let compass = WeatherUnits.compassAbbreviation(
            degrees: point.weather.wind.directionDegrees
        )
        return "\(compass) \(Int(speed.rounded())) mph"
    }

    private var pressure: String {
        guard let value = point.weather.pressureHPa, value.isFinite else {
            return "Unavailable"
        }
        return "\(Int(value.rounded())) hPa"
    }

    private var decisionTime: String {
        if isCurrentHour { return "Right now" }
        return ForecastDateFormatting.string(
            from: point.date,
            presentation: .dateTime,
            timeZone: timeZone,
            locale: locale
        )
    }

    private var windowText: String {
        guard let window else { return "No nearby solunar window" }
        if window.isActive(at: point.date) {
            return "\(window.period.rawValue) window active"
        }
        let time = ForecastDateFormatting.string(
            from: window.peak,
            presentation: .hour,
            timeZone: timeZone,
            locale: locale
        )
        return "Next \(window.period.rawValue.lowercased()) window at \(time)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    decisionCopy
                    Spacer(minLength: 12)
                    scoreReadout
                }
                VStack(alignment: .leading, spacing: 14) {
                    decisionCopy
                    scoreReadout
                }
            }

            metrics
        }
        .padding(dynamicTypeSize.isAccessibilitySize ? 18 : 20)
        .background(heroBackground, in: .rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke((band?.color ?? Ink.hullLine).opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("BiteTime decision for \(species.displayName)")
        .accessibilityValue(accessibilitySummary)
        .accessibilityIdentifier("bitetime.hero")
    }

    private var decisionCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(decisionTime)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Ink.brass)
            Text(species == .all ? "Overall bite outlook" : species.displayName)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Ink.chart)
                .fixedSize(horizontal: false, vertical: true)
            Text(windowText)
                .font(.system(.callout, design: .rounded, weight: .medium))
                .foregroundStyle(Ink.chartDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scoreReadout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(score.map(String.init) ?? "—")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(band?.color ?? Ink.chartDim)
            VStack(alignment: .leading, spacing: 1) {
                Text("/ 100")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.chartDim)
                Text(band?.title ?? "Unavailable")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Ink.chart)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var metrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                metric("Air", value: temperature, symbol: point.weather.symbolName)
                metric("Wind", value: wind, symbol: "wind")
                metric("Pressure", value: pressure, symbol: "barometer")
            }
            VStack(spacing: 10) {
                metric("Air", value: temperature, symbol: point.weather.symbolName)
                metric("Wind", value: wind, symbol: "wind")
                metric("Pressure", value: pressure, symbol: "barometer")
            }
        }
    }

    private func metric(
        _ label: String,
        value: String,
        symbol: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Ink.chartDim)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.chartDim)
                Text(value)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Ink.chart)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(Ink.abyss.opacity(0.34), in: .rect(cornerRadius: 15))
    }

    private var heroBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                (band?.color ?? Ink.tide).opacity(0.22),
                Ink.card.opacity(0.98),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var accessibilitySummary: String {
        [
            decisionTime,
            score.map { "bite score \($0) out of 100" } ?? "bite score unavailable",
            band?.title,
            point.weather.conditionText,
            temperature,
            "wind \(wind)",
            "pressure \(pressure)",
            windowText,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}
