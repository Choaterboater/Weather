import SwiftUI

/// Compact, conditions-aware bait decision shown near the top of BiteTime.
/// External artwork, retailers, tutorials, and Q&A are absent from this view;
/// they become reachable only through the explicit `More advice` action.
struct BestBaitTodayView: View {
    let context: BestBaitContext?
    let species: Species
    let engine: BaitEngine
    let provenance: WeatherProvenance

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsFullReason = false
    @State private var showsMoreAdvice = false

    private struct RequestIdentity: Hashable {
        let species: Species
        let contextKey: BaitContextKey?
    }

    private var requestIdentity: RequestIdentity {
        RequestIdentity(species: species, contextKey: context?.key)
    }

    private var matchingResult: BestBaitResult? {
        guard species != .all,
              let context,
              engine.result?.key == context.key else { return nil }
        return engine.result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Best Bait Today", systemImage: "fish.fill")
            content
        }
        .accessibilityIdentifier("bitetime.bestBait")
        .task(id: requestIdentity) {
            await engine.generateBestBait(
                for: species,
                context: context
            )
        }
        .sheet(isPresented: $showsMoreAdvice) {
            if let context {
                BaitEngineView(
                    context: context,
                    engine: engine,
                    provenance: provenance
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if species == .all {
            GlassCard {
                Label(
                    "Choose a specific species to get a best-bait pick.",
                    systemImage: "scope"
                )
                .font(.body)
                .foregroundStyle(Ink.chartDim)
            }
        } else if context == nil {
            GlassCard {
                Label(
                    "A selected forecast hour is needed for today's bait pick.",
                    systemImage: "clock.badge.exclamationmark"
                )
                .font(.body)
                .foregroundStyle(Ink.chartDim)
            }
        } else if let matchingResult {
            recommendationCard(matchingResult)
        } else {
            GlassCard {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Choosing for the selected hour…")
                        .font(.body)
                        .foregroundStyle(Ink.chartDim)
                }
            }
        }
    }

    private func recommendationCard(
        _ result: BestBaitResult
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.recommendation.topBait)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Ink.chart)
                        if let color = result.presentationColor {
                            Text(color)
                                .font(.callout)
                                .foregroundStyle(Ink.chartDim)
                        }
                    }

                    HStack(alignment: .top, spacing: 20) {
                        detail(
                            label: "Technique",
                            value: result.recommendation.technique,
                            systemImage: "figure.fishing"
                        )
                        detail(
                            label: result.presentationDetailLabel,
                            value: result.presentationDetailValue,
                            systemImage: result.presentationDetailSystemImage
                        )
                    }

                    Text(result.recommendation.whyReason)
                        .font(.body)
                        .foregroundStyle(Ink.chartDim)
                        .lineLimit(showsFullReason ? nil : 2)

                    provenance(result)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Best bait today")
                .accessibilityValue(accessibilityValue(for: result))

                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalActionButtons
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    whyButton
                    refreshButton
                    moreAdviceButton
                }
                .fixedSize(horizontal: true, vertical: false)

                verticalActionButtons
            }
        }
    }

    private var verticalActionButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            whyButton
            refreshButton
            moreAdviceButton
        }
    }

    private var whyButton: some View {
        Button(
            showsFullReason ? "Hide reason" : "Why this pick",
            systemImage: "info.circle"
        ) {
            showsFullReason.toggle()
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(minHeight: 44)
    }

    private var refreshButton: some View {
        Button("Refresh", systemImage: "arrow.clockwise") {
            Task {
                await engine.generateBestBait(
                    for: species,
                    context: context,
                    force: true
                )
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(minHeight: 44)
        .disabled(engine.status == .working)
    }

    private var moreAdviceButton: some View {
        Button("More advice", systemImage: "ellipsis.circle") {
            showsMoreAdvice = true
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(minHeight: 44)
    }

    private func provenance(_ result: BestBaitResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(result.sourceLabel, systemImage: provenanceSymbol(result))
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    result.generatedAt == nil ? Ink.brass : Ink.bite
                )
            if let generatedAt = result.generatedAt {
                Text(
                    "Generated "
                        + generatedAt.formatted(
                            date: .omitted,
                            time: .shortened
                        )
                )
                .font(.caption)
                .foregroundStyle(Ink.chartDim)
            }
        }
    }

    private func detail(
        label: String,
        value: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(Ink.chartDim)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Ink.chart)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func provenanceSymbol(_ result: BestBaitResult) -> String {
        result.generatedAt == nil ? "book.closed" : "apple.intelligence"
    }

    private func accessibilityValue(for result: BestBaitResult) -> String {
        var parts = [
            result.recommendation.topBait,
            "Technique: \(result.recommendation.technique)",
            "\(result.presentationDetailLabel): "
                + result.presentationDetailValue,
            result.recommendation.whyReason,
            result.sourceLabel,
        ]
        if let color = result.presentationColor {
            parts.insert(color, at: 1)
        }
        if let generatedAt = result.generatedAt {
            parts.append(
                "Generated "
                    + generatedAt.formatted(
                        date: .omitted,
                        time: .shortened
                    )
            )
        }
        return parts.joined(separator: ". ")
    }
}
