import SwiftUI

/// Species encyclopedia — grid of cards, filterable by water type. Tapping a
/// card opens SpeciesDetailView with regulations and tackle guidance.
struct SpeciesGuideView: View {
    @Environment(SpotStore.self) private var spots
    @State private var waterFilter: WaterType? = nil

    /// Inferred default filter: if the active spot is saltwater, start there.
    private var defaultFilter: WaterType? {
        spots.selectedSpot?.waterType
    }

    private var species: [Species] {
        Species.allCases.filter { $0 != .all && $0.isAvailable(for: waterFilter) }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                filterChips
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
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [Color.indigo.opacity(0.18), .cyan.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .onAppear {
            if waterFilter == nil, let inferred = defaultFilter {
                waterFilter = inferred
            }
        }
    }

    @ViewBuilder
    private var filterChips: some View {
        HStack(spacing: 8) {
            chip(title: "All", isSelected: waterFilter == nil) {
                waterFilter = nil
            }
            ForEach(WaterType.allCases.filter { $0 != .brackish }) { type in
                chip(
                    title: type.displayName,
                    systemImage: type.symbolName,
                    isSelected: waterFilter == type
                ) {
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
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(.thinMaterial),
                in: .capsule
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

private struct SpeciesCard: View {
    let species: Species

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [species.tint.opacity(0.35), species.tint.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "fish.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(species.tint)
                        .symbolEffect(.bounce, options: .nonRepeating)
                }
                .frame(height: 90)

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
