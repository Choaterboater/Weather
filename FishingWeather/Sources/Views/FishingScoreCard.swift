import Charts
import SwiftUI

/// Headline card on the Fishing tab: a glanceable 0–100 number with a
/// stacked-bar contribution chart and an expandable factor breakdown.
struct FishingScoreCard: View {
    let score: FishingScore
    @State private var isExpanded = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("\(score.overall)")
                        .font(.system(size: 56, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText(value: Double(score.overall)))
                        .foregroundStyle(score.tint)
                        .accessibilityLabel("Fishing score \(score.overall) out of 100")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(score.summary)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(score.tint)
                        Text("Today's fishing score")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                contributionBar

                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(score.factors) { factor in
                            FactorRow(factor: factor)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Why this score", systemImage: "info.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: isExpanded)
    }

    private var contributionBar: some View {
        Chart {
            ForEach(score.factors) { factor in
                BarMark(
                    x: .value("Points", factor.contribution),
                    y: .value("Score", "factors")
                )
                .foregroundStyle(by: .value("Factor", factor.label))
                .annotation(position: .overlay) {
                    if factor.contribution >= 6 {
                        Text("\(factor.contribution)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .chartXScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
        .frame(height: 56)
    }
}

private struct FactorRow: View {
    let factor: ScoreFactor

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: factor.symbolName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(factor.label)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("+\(factor.contribution)")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text(factor.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
