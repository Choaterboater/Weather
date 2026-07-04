import SwiftUI

/// Headline of the Fishing tab: the Bite Gauge — a marine-instrument dial that
/// reads today's 0–100 fishing score — with an expandable factor breakdown
/// styled as instrument readouts.
struct FishingScoreCard: View {
    let score: FishingScore
    @State private var isExpanded = false

    var body: some View {
        InstrumentPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Today's bite")
                    .instrumentLabel(Ink.brass)

                ZStack {
                    BiteGauge(score: score.overall)
                        .frame(height: 158)
                    VStack(spacing: 2) {
                        Text("\(score.overall)")
                            .font(.system(size: 50, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Ink.chart)
                            .contentTransition(.numericText(value: Double(score.overall)))
                        Text(score.summary)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(3)
                            .textCase(.uppercase)
                            .foregroundStyle(Ink.band(for: score.overall))
                    }
                    .offset(y: -6)
                    .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement()
                .accessibilityLabel("Fishing score \(score.overall) out of 100, \(score.summary)")

                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(spacing: 12) {
                        ForEach(score.factors) { factor in
                            InstrumentReadout(factor: factor)
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    Text("Why this score")
                        .instrumentLabel()
                }
                .tint(Ink.chartDim)
            }
        }
        .sensoryFeedback(.selection, trigger: isExpanded)
    }
}

/// One factor as an instrument readout: a tracked label, a favorability bar
/// tinted by how good the factor is, and its point contribution in mono.
private struct InstrumentReadout: View {
    let factor: ScoreFactor

    private var barColor: Color {
        switch factor.raw {
        case 0.66...: Ink.bite
        case 0.4..<0.66: Ink.brass
        default: Ink.slack
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Image(systemName: factor.symbolName)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.chartDim)
                    .frame(width: 18)
                Text(factor.label)
                    .instrumentLabel(Ink.chart)
                Spacer()
                Text("+\(factor.contribution)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Ink.chart)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.hullLine)
                    Capsule().fill(barColor)
                        .frame(width: max(3, geo.size.width * CGFloat(min(1, factor.raw))))
                }
            }
            .frame(height: 4)
            Text(factor.detail)
                .font(.system(size: 11))
                .foregroundStyle(Ink.chartDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
