#if DEBUG
import SwiftUI

/// TEMPORARY verification harness — renders components with fixed mock data so
/// they can be screenshotted on the simulator without WeatherKit/live location.
/// Gated behind `-uiPreview <name>`. Remove before committing.
struct DebugPreviewHost: View {
    var body: some View {
        if CommandLine.arguments.contains("scorecard") {
            DebugScoreCard()
        } else {
            Text("Unknown -uiPreview target")
        }
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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FishingScoreCard(score: score)
            }
            .padding(.horizontal)
            .padding(.top, 20)
        }
        .background(Ink.backdrop)
    }
}
#endif
