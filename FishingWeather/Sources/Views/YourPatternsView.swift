import SwiftUI

/// The "Your Patterns" sheet: what the catch log taught the Fishing Score —
/// which factors it now leans on, the conditions that produce fish, and the top
/// baits. Reached by tapping the "Tuned" badge on the score card. Presentational.
struct YourPatternsView: View {
    let insights: PersonalInsights?
    let species: Species
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let insights {
                        loaded(insights)
                    } else {
                        empty
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Ink.backdrop)
            .navigationTitle("Your Patterns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// "bass " for a specific species, "" for All — so the copy reads naturally.
    private var subject: String {
        species == .all ? "" : species.displayName.lowercased() + " "
    }

    private func loaded(_ insights: PersonalInsights) -> some View {
        GlassCardStack(spacing: 16) {
            header(count: insights.catchCount)
            factorSection(insights.factorChanges)
            if !insights.conditions.isEmpty {
                conditionSection(insights.conditions)
            }
            if !insights.topBaits.isEmpty {
                baitSection(insights.topBaits)
            }
            disclaimer
        }
    }

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tuned to you")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(Ink.chart)
            Text("Learned from your \(count) \(subject)\(count == 1 ? "catch" : "catches")")
                .instrumentLabel(Ink.brass)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func factorSection(_ changes: [PersonalInsights.FactorChange]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "What your score leans on", systemImage: "slider.horizontal.3")
            GlassCard {
                VStack(spacing: 12) {
                    ForEach(changes) { change in
                        HStack(spacing: 12) {
                            Image(systemName: change.kind.symbolName)
                                .frame(width: 22)
                                .foregroundStyle(Ink.chartDim)
                            Text(change.label)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(Ink.chart)
                            Spacer()
                            directionTag(change.direction)
                        }
                    }
                }
            }
        }
    }

    private func directionTag(_ direction: PersonalInsights.FactorChange.Direction) -> some View {
        let icon: String
        let label: String
        let color: Color
        switch direction {
        case .up: icon = "arrow.up"; label = "More"; color = Ink.brass
        case .down: icon = "arrow.down"; label = "Less"; color = Ink.chartDim
        case .steady: icon = "minus"; label = "Standard"; color = Ink.chartDim
        }
        return HStack(spacing: 4) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(color)
    }

    private func conditionSection(_ conditions: [PersonalInsights.ConditionStat]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "When you catch", systemImage: "checklist")
            GlassCard {
                VStack(spacing: 12) {
                    ForEach(conditions) { stat in
                        HStack(spacing: 12) {
                            Image(systemName: stat.icon)
                                .frame(width: 22)
                                .foregroundStyle(Ink.brass)
                            Text(stat.label)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(Ink.chart)
                            Spacer()
                            Text(stat.detail)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Ink.chartDim)
                        }
                    }
                }
            }
        }
    }

    private func baitSection(_ baits: [PersonalInsights.BaitCount]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Top baits", systemImage: "fish")
            GlassCard {
                VStack(spacing: 12) {
                    ForEach(baits) { bait in
                        HStack {
                            Text(bait.bait)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(Ink.chart)
                            Spacer()
                            Text("×\(bait.count)")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Ink.brass)
                        }
                    }
                }
            }
        }
    }

    private var disclaimer: some View {
        Text("BiteCast nudges your score toward the conditions you actually catch on — it never overrides the fundamentals. More catches, sharper tuning.")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Ink.chartDim)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("No patterns yet", systemImage: "sparkles")
        } description: {
            Text("Log 5+ \(subject)catches and BiteCast starts tuning your score to the conditions that work for you.")
        }
        .padding(.top, 80)
    }
}
