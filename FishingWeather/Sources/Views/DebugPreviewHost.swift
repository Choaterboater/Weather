#if DEBUG
import SwiftUI

/// TEMPORARY verification harness — renders components with fixed mock data so
/// they can be screenshotted on the simulator without WeatherKit/live location.
/// Gated behind `-uiPreview <name>`. Remove before committing.
struct DebugPreviewHost: View {
    var body: some View {
        if CommandLine.arguments.contains("guide") {
            NavigationStack { SpeciesGuideView() }
                .environment(SpotStore())
        } else if CommandLine.arguments.contains("scout") {
            NavigationStack { ScoutView() }
                .environment(WeatherStore())
                .environment(SpotStore())
                .environment(LocationManager())
        } else if CommandLine.arguments.contains("log") {
            NavigationStack { CatchLogView() }
                .environment(CatchLog())
        } else if CommandLine.arguments.contains("tide") {
            DebugTideCard()
        } else if CommandLine.arguments.contains("scorecard") {
            DebugScoreCard()
        } else {
            Text("Unknown -uiPreview target")
        }
    }
}

private struct DebugTideCard: View {
    private let start = Date.now.addingTimeInterval(-6 * 3600)

    private var samples: [TideSample] {
        (0..<49).map { i in
            let t = Double(i) * 0.5 // hours
            let h = 2.6 + 1.7 * sin((t / 12.42) * 2 * .pi + 1.0)
            return TideSample(time: start.addingTimeInterval(t * 3600), heightFeet: h)
        }
    }

    private var events: [TideEvent] {
        [
            TideEvent(time: start.addingTimeInterval(1.8 * 3600), kind: .low, heightFeet: 0.9),
            TideEvent(time: start.addingTimeInterval(8.0 * 3600), kind: .high, heightFeet: 4.3),
            TideEvent(time: start.addingTimeInterval(14.2 * 3600), kind: .low, heightFeet: 0.9),
            TideEvent(time: start.addingTimeInterval(20.4 * 3600), kind: .high, heightFeet: 4.3),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TideCard(events: events, samples: samples,
                         stationName: "Fort De Soto", distanceMiles: 3, isLoading: false)
            }
            .padding(.horizontal)
            .padding(.top, 20)
        }
        .background(Ink.backdrop)
    }
}

private struct DebugScoreCard: View {
    private let score = FishingScore(factors: [
        ScoreFactor(kind: .solunar, label: "Solunar", weight: 0.25, raw: 0.92,
                    detail: "Full moon — major bite window active until 8:00 AM"),
        ScoreFactor(kind: .pressure, label: "Pressure", weight: 0.20, raw: 0.95,
                    detail: "Falling — a dropping barometer ahead of a front turns fish on"),
        ScoreFactor(kind: .wind, label: "Wind", weight: 0.15, raw: 0.85,
                    detail: "8 mph SE — light chop, good visibility under the surface"),
        ScoreFactor(kind: .tide, label: "Tide", weight: 0.25, raw: 0.90,
                    detail: "Strong moving water — prime tide. Next tide in 2 hr"),
        ScoreFactor(kind: .season, label: "Season", weight: 0.15, raw: 0.35,
                    detail: "Shoulder month for redfish"),
    ])

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private var samples: [HourSample] {
        (0..<24).map { i in
            HourSample(
                date: start.addingTimeInterval(Double(i) * 3600),
                temperature: 75,
                pressureHPa: 1016 - Double(i) * 0.34,
                precipChance: 0,
                windSpeedMph: 9 + 5 * sin(Double(i) / 3.0),
                windGustMph: 14 + 7 * sin(Double(i) / 3.0)
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FishingScoreCard(score: score)

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Barometer", systemImage: "barometer")
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("1013 hPa")
                                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                                Label("Falling", systemImage: "arrow.down.right")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Ink.bite)
                                Spacer()
                            }
                            Text("A dropping barometer ahead of a front is the textbook trigger.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            PressureTrendChart(samples: samples,
                                               now: start.addingTimeInterval(3 * 3600))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Wind", systemImage: "wind")
                    GlassCard {
                        WindForecastChart(samples: samples,
                                          now: start.addingTimeInterval(3 * 3600))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(Ink.backdrop)
    }
}
#endif
