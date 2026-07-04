import SwiftUI

/// Species encyclopedia — grid of cards, filterable by water type. Tapping a
/// card opens SpeciesDetailView with regulations and tackle guidance.
struct SpeciesGuideView: View {
    @Environment(SpotStore.self) private var spots
    @State private var waterFilter: WaterType? = nil
    /// Once the user taps a chip, stop auto-applying the spot's water type.
    @State private var userPickedFilter = false
    @State private var didApplyDefault = false

    /// Inferred default filter: salt/fresh from the active spot; brackish → All.
    private var defaultFilter: WaterType? {
        guard let type = spots.selectedSpot?.waterType, type != .brackish else { return nil }
        return type
    }

    private var species: [Species] {
        Species.allCases.filter { $0 != .all && $0.isAvailable(for: waterFilter) }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            // mergeSpacing below the 12pt grid gap: at the default the glass
            // cards weld together across the grid's column gutter.
            GlassCardStack(spacing: 16, mergeSpacing: 8) {
                filterChips
                if species.isEmpty {
                    ContentUnavailableView(
                        "No species for this filter",
                        systemImage: "fish",
                        description: Text("Try All, or pick freshwater or saltwater.")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(species) { species in
                            NavigationLink {
                                SpeciesDetailView(species: species)
                            } label: {
                                SpeciesCard(species: species)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Ink.backdrop)
        .onAppear(perform: applyDefaultFilter)
        .onChange(of: spots.selectedSpotID) {
            guard !userPickedFilter else { return }
            didApplyDefault = false
            applyDefaultFilter()
        }
    }

    private func applyDefaultFilter() {
        guard !userPickedFilter, !didApplyDefault else { return }
        waterFilter = defaultFilter
        didApplyDefault = true
    }

    @ViewBuilder
    private var filterChips: some View {
        HStack(spacing: 8) {
            chip(title: "All", isSelected: waterFilter == nil) {
                userPickedFilter = true
                waterFilter = nil
            }
            ForEach(WaterType.allCases.filter { $0 != .brackish }) { type in
                chip(
                    title: type.displayName,
                    systemImage: type.symbolName,
                    isSelected: waterFilter == type
                ) {
                    userPickedFilter = true
                    waterFilter = type
                }
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private func chip(
        title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? AnyShapeStyle(Ink.brass)
                    : AnyShapeStyle(.thinMaterial),
                in: .capsule
            )
            .foregroundStyle(isSelected ? Ink.abyss : Color.primary)
        }
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

private struct SpeciesCard: View {
    let species: Species

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SpeciesPhotoView(species: species, size: .card)
                    .frame(height: 110)
                    .clipShape(.rect(cornerRadius: 16))

                Text(species.displayName)
                    .font(.headline)
                    .lineLimit(1)
                if let scientific = species.scientificName {
                    Text(scientific)
                        .font(.caption2.italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let waterType = species.waterType {
                    Label(waterType.displayName, systemImage: waterType.symbolName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
