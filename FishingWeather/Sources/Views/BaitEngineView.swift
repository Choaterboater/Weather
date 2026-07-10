import SwiftUI

struct BaitEngineView: View {
    let conditions: FishingConditions
    let species: Species
    var tideEvents: [TideEvent] = []
    let engine: BaitEngine

    @State private var question = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "AI Bait Engine", systemImage: "sparkles")

            content
        }
        .animation(.smooth(duration: 0.35), value: engine.status)
        .sensoryFeedback(trigger: engine.status) { _, newValue in
            switch newValue {
            case .ready: .success
            case .failed: .error
            default: nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch engine.status {
            case .idle:
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Get an on-device bait recommendation tuned to right now's conditions.")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                        Button("Get recommendation", systemImage: "wand.and.stars") {
                            Task {
                                await engine.generate(
                                    conditions: conditions,
                                    species: species,
                                    tideEvents: tideEvents
                                )
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    }
                }
            case .working:
                GlassCard {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Reading the water…")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    }
                }
            case .unavailable(let message):
                GlassCard {
                    Label(message, systemImage: "exclamationmark.bubble")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
                }
            case .failed(let message):
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Couldn't generate advice", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.chart)
                        Text(message)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                        Button("Try again") {
                            Task {
                                await engine.generate(
                                    conditions: conditions,
                                    species: species,
                                    tideEvents: tideEvents
                                )
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            case .ready:
                if let report = engine.report {
                    GlassCard {
                        Text(report)
                            .font(.callout)
                    }
                }
                if let recommendation = engine.recommendation {
                    BaitCard(recommendation: recommendation, species: species)
                }
                askBox
            }
        }
    }

    private var askBox: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(engine.answers) { qa in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(qa.question)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.chart)
                        Text(qa.answer)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    }
                }
                HStack {
                    TextField("Ask anything — “why aren’t they biting?”", text: $question)
                        .textFieldStyle(.plain)
                        .onSubmit(submit)
                    Button(action: submit) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Send question")
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || engine.isAnswering)
                }
                if engine.isAnswering {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private func submit() {
        let q = question
        question = ""
        Task { await engine.ask(q) }
    }
}

private struct BaitCard: View {
    let recommendation: BaitRecommendation
    let species: Species

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                BaitArtView(recommendation: recommendation, species: species)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recommendation.topBait)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.chart)
                        Text(recommendation.color)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    }
                    Spacer()
                    ConfidenceBadge(value: recommendation.confidence)
                }

                HStack(spacing: 24) {
                    DetailItem(label: "Technique", value: recommendation.technique, systemImage: "figure.fishing")
                    DetailItem(label: "Depth", value: recommendation.depth, systemImage: "arrow.down.to.line")
                }

                Text(recommendation.whyReason)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.chartDim)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bait recommendation")
        .accessibilityValue("\(recommendation.topBait), \(recommendation.color). \(recommendation.confidence) percent confidence. Technique: \(recommendation.technique). Depth: \(recommendation.depth). \(recommendation.whyReason)")
    }
}

private struct ConfidenceBadge: View {
    let value: Int

    private var tint: Color {
        switch value {
        case 70...: Ink.bite
        case 40..<70: Ink.brass
        default: Ink.slack
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)%")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text("confidence")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Ink.chartDim)
        }
    }
}

private struct DetailItem: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: systemImage)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Ink.chartDim)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Ink.chart)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
