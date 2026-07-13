import SwiftUI

/// Community is intentionally local-only until there is a real sharing model.
/// This view never invents activity, profiles, or connectivity state.
struct CommunityPlaceholderView: View {
    let openMap: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                privacyCard
                localActions
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .background(Ink.backdrop)
    }

    private var privacyCard: some View {
        InstrumentPanel {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "person.2.slash.fill")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.brass)
                    .frame(width: 56, height: 56)
                    .background(Ink.brass.opacity(0.12), in: .circle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Private by design")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Ink.chart)
                    Text("Community sharing is not connected yet. BiteCast does not publish profiles, catches, or saved water from this screen.")
                        .font(.body)
                        .foregroundStyle(Ink.chartDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label("Your local tools remain available below.", systemImage: "iphone")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Ink.tide)
            }
        }
    }

    private var localActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Your local water", systemImage: "lock.shield")

            NavigationLink {
                CatchLogView()
                    .navigationTitle("Catch Log")
            } label: {
                actionLabel(
                    title: "Review Catch Log",
                    detail: "See the catches stored in your log.",
                    systemImage: "book.closed.fill"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Review Catch Log")
            .accessibilityHint("Opens your local catch history")

            Button(action: openMap) {
                actionLabel(
                    title: "Explore the Map",
                    detail: "Return to your saved and nearby water.",
                    systemImage: "map.fill"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Explore the Map")
            .accessibilityHint("Switches to the Map destination")
        }
    }

    private func actionLabel(
        title: String,
        detail: String,
        systemImage: String
    ) -> some View {
        InstrumentPanel {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.brass)
                    .frame(width: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Ink.chart)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Ink.chartDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Ink.chartDim)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        }
    }
}
