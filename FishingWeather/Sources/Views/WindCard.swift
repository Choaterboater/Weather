import SwiftUI
import WeatherKit

/// WeatherKit adapter: extracts the scalars `WindPanel` needs from the opaque
/// `CurrentWeather`, so the presentation layer stays testable and previewable.
struct WindCard: View {
    let current: CurrentWeather
    let samples: [HourSample]
    var now: Date = .now

    var body: some View {
        WindPanel(
            compass: current.wind.compassDirection.abbreviation,
            fromDegrees: current.wind.direction.converted(to: .degrees).value,
            speedMph: current.wind.speed.converted(to: .milesPerHour).value,
            gustMph: current.wind.gust?.converted(to: .milesPerHour).value,
            samples: samples,
            now: now
        )
    }
}

/// Wind panel for the weather dashboard: current speed/direction/gust with a
/// small compass, a fishing-oriented descriptor, and a 24-hour shaded forecast.
/// Decoupled from WeatherKit (plain values in) — same philosophy as HourSample.
struct WindPanel: View {
    let compass: String
    let fromDegrees: Double
    let speedMph: Double
    let gustMph: Double?
    let samples: [HourSample]
    var now: Date = .now

    private var speedText: String { Self.mph(speedMph) }
    private var gustText: String? { gustMph.map(Self.mph) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Wind", systemImage: "wind")
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        WindCompass(fromDegrees: fromDegrees, compass: compass)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(compass) \(speedText)")
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(Ink.chart)
                                .contentTransition(.numericText())
                            if let gustText {
                                Text("Gusts \(gustText)")
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Ink.chartDim)
                            }
                            Text(Self.descriptor(forMph: speedMph))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Ink.chartDim)
                        }
                        Spacer()
                    }

                    if samples.contains(where: { $0.windSpeedMph > 0 }) {
                        WindForecastChart(samples: samples, now: now)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Wind")
        .accessibilityValue("From \(compass) at \(speedText).\(gustText.map { " Gusts \($0)." } ?? "") \(Self.descriptor(forMph: speedMph)).")
    }

    private static func mph(_ value: Double) -> String {
        Measurement(value: value, unit: UnitSpeed.milesPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }

    /// Plain-language read on what the sustained wind means on the water.
    nonisolated static func descriptor(forMph mph: Double) -> String {
        switch mph {
        case ..<5: "Calm — glassy water"
        case ..<10: "Light breeze — prime conditions"
        case ..<15: "Breezy — a little chop"
        case ..<20: "Windy — casting gets tricky"
        default: "Strong — small-craft caution"
        }
    }
}

/// A compact compass dial. The arrow points the way the wind is *blowing*
/// (meteorological direction is where it comes FROM, so we render from + 180),
/// which reads more naturally than a "coming-from" arrow.
private struct WindCompass: View {
    let fromDegrees: Double
    let compass: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Ink.hullLine.opacity(0.5), lineWidth: 1.5)
            Text("N")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Ink.chartDim)
                .offset(y: -20)
            Image(systemName: "arrow.up")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Ink.bite)
                .rotationEffect(.degrees(fromDegrees + 180))
        }
        .frame(width: 54, height: 54)
        .accessibilityHidden(true)
    }
}

#Preview("Wind") {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let samples = (0..<24).map { i in
        HourSample(
            date: start.addingTimeInterval(Double(i) * 3600),
            temperature: 75,
            pressureHPa: 1015,
            precipChance: 0,
            windSpeedMph: 9 + 6 * sin(Double(i) / 3.0),
            windGustMph: 14 + 8 * sin(Double(i) / 3.0)
        )
    }
    return ScrollView {
        WindPanel(compass: "NW", fromDegrees: 315, speedMph: 11, gustMph: 18,
                  samples: samples, now: start)
            .padding()
    }
}
