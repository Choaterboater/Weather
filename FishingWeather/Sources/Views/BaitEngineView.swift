import SwiftUI

/// Secondary advice intentionally constructed only after the angler chooses
/// `More advice` on the compact Best Bait Today card.
struct BaitEngineView: View {
    let context: BestBaitContext
    let engine: BaitEngine
    let provenance: WeatherProvenance

    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var forecastExpired = false

    private var result: BestBaitResult? {
        guard engine.result?.key == context.key else { return nil }
        return engine.result
    }

    var body: some View {
        NavigationStack {
            Group {
                if canDisplayForecast {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if let attribution = provenance.providerAttribution {
                                WeatherSourceAttributionView(attribution: attribution)
                                ModifiedWeatherDataNotice(attribution: attribution)
                                ForecastSafetyNotice()
                            }
                            if let result {
                                optionalReport(result)
                                whySection(result)
                                BaitArtView(
                                    recommendation: result.recommendation,
                                    species: context.species
                                )
                                YouTubeVideoCarousel(
                                    title: "Tutorials",
                                    query: "How to fish "
                                        + result.recommendation.topBait
                                        + " for \(context.species.displayName)"
                                )
                                questionSection
                            } else {
                                ContentUnavailableView(
                                    "Advice changed",
                                    systemImage: "arrow.triangle.2.circlepath",
                                    description: Text(
                                        "Close this view to load advice for the active forecast hour."
                                    )
                                )
                            }
                        }
                        .padding()
                    }
                } else {
                    ContentUnavailableView(
                        "Forecast expired",
                        systemImage: "clock.badge.exclamationmark",
                        description: Text(
                            "Close this view and refresh BiteTime before using this advice."
                        )
                    )
                    .padding()
                }
            }
            .background(Ink.backdrop)
            .navigationTitle("More advice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: result?.key) {
            guard canDisplayForecast else { return }
            await engine.generateMoreAdvice(for: context)
        }
        .task(id: provenance.expiresAt) {
            await enforceExpiryBoundary()
        }
    }

    private var canDisplayForecast: Bool {
        !forecastExpired && WeatherDerivedContentPolicy.canDisplay(provenance)
    }

    @MainActor
    private func enforceExpiryBoundary() async {
        forecastExpired = false
        guard let delay = WeatherDerivedContentPolicy.secondsUntilExpiry(
            provenance
        ) else {
            forecastExpired = true
            return
        }
        do {
            try await Task.sleep(for: .seconds(max(delay, 0.01)))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        forecastExpired = true
    }

    @ViewBuilder
    private func optionalReport(_ result: BestBaitResult) -> some View {
        if case .onDeviceAppleIntelligence = result.source {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(
                    title: "Selected-hour report",
                    systemImage: "text.quote"
                )
                GlassCard {
                    if let report = engine.report {
                        Text(report)
                            .font(.body)
                            .foregroundStyle(Ink.chart)
                    } else if engine.isGeneratingAdvice {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Reading the selected hour…")
                                .font(.body)
                                .foregroundStyle(Ink.chartDim)
                        }
                    } else if let adviceError = engine.adviceError {
                        Label(
                            adviceError,
                            systemImage: "exclamationmark.bubble"
                        )
                        .font(.body)
                        .foregroundStyle(Ink.chartDim)
                    }
                }
            }
        }
    }

    private func whySection(_ result: BestBaitResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Why this pick", systemImage: "text.magnifyingglass")
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(result.recommendation.whyReason)
                        .font(.body)
                        .foregroundStyle(Ink.chart)

                    Divider()
                        .overlay(Ink.hullLine)

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
            }
        }
    }

    @ViewBuilder
    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Ask a follow-up", systemImage: "bubble.left.and.text.bubble.right")
            GlassCard {
                if engine.canAnswer {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(engine.answers) { qa in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(qa.question)
                                    .font(.headline)
                                    .foregroundStyle(Ink.chart)
                                Text(qa.answer)
                                    .font(.body)
                                    .foregroundStyle(Ink.chartDim)
                            }
                        }

                        HStack {
                            TextField(
                                "Ask about this selected hour",
                                text: $question
                            )
                            .textFieldStyle(.plain)
                            .onSubmit(submit)

                            Button(action: submit) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Ink.bite)
                            }
                            .accessibilityLabel("Send question")
                            .disabled(
                                question.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty || engine.isAnswering
                            )
                        }

                        if engine.isAnswering {
                            ProgressView().controlSize(.small)
                        }
                    }
                } else {
                    Text(
                        "Follow-up Q&A requires a current on-device Apple Intelligence result."
                    )
                    .font(.body)
                    .foregroundStyle(Ink.chartDim)
                }
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
                .font(.body.weight(.semibold))
                .foregroundStyle(Ink.chart)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submit() {
        let submitted = question
        question = ""
        Task { await engine.ask(submitted) }
    }
}
