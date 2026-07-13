import SwiftUI

struct YouView: View {
    @State private var showsSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                personalHeader
                library
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .background(Ink.backdrop)
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
    }

    private var personalHeader: some View {
        InstrumentPanel {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "figure.fishing")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.brass)
                    .frame(width: 52, height: 52)
                    .background(Ink.brass.opacity(0.12), in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your water. Your history.")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Ink.chart)
                    Text("Catch records, field tools, and preferences stay together here.")
                        .font(.subheadline)
                        .foregroundStyle(Ink.chartDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Your field kit", systemImage: "backpack.fill")
            InstrumentPanel {
                VStack(spacing: 0) {
                    destinationLink(
                        title: "Catch Log",
                        detail: "Review catches and patterns",
                        systemImage: "book.closed.fill"
                    ) {
                        CatchLogView()
                            .navigationTitle("Catch Log")
                    }
                    divider
                    destinationLink(
                        title: "Species Guide",
                        detail: "Identification, habitat, and tackle",
                        systemImage: "book.pages.fill"
                    ) {
                        SpeciesGuideView()
                            .navigationTitle("Species Guide")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    divider
                    destinationLink(
                        title: "Scout the Water",
                        detail: "Read structure from a photo",
                        systemImage: "camera.viewfinder"
                    ) {
                        ScoutView()
                            .navigationTitle("Scout the Water")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    divider
                    destinationLink(
                        title: "Saved Spots",
                        detail: "Return to water you keep",
                        systemImage: "mappin.and.ellipse"
                    ) {
                        SavedSpotsView()
                            .navigationTitle("Saved Spots")
                    }
                    divider
                    Button {
                        showsSettings = true
                    } label: {
                        rowLabel(
                            title: "Settings",
                            detail: "Alerts and preferences",
                            systemImage: "gearshape.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens app settings")
                }
            }
        }
    }

    private var divider: some View {
        Divider()
            .overlay(Ink.hullLine.opacity(0.7))
            .padding(.leading, 46)
    }

    private func destinationLink<Destination: View>(
        title: String,
        detail: String,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            rowLabel(title: title, detail: detail, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    private func rowLabel(
        title: String,
        detail: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(Ink.brass)
                .frame(width: 34, height: 34)
                .background(Ink.brass.opacity(0.1), in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.chart)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Ink.chartDim)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Ink.chartDim)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 56)
        .contentShape(.rect)
    }
}

private struct SavedSpotsView: View {
    @Environment(SpotStore.self) private var spots

    var body: some View {
        Group {
            if spots.spots.isEmpty {
                ContentUnavailableView {
                    Label("No saved spots", systemImage: "mappin.slash")
                } description: {
                    Text("Save water from the Map to keep it close here.")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(spots.spots) { spot in
                            NavigationLink {
                                SpotDetailView(spot: spot)
                            } label: {
                                SpotCard(
                                    spot: spot,
                                    distanceMiles: nil,
                                    isActive: spots.selectedSpotID == spot.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(Ink.backdrop)
    }
}
