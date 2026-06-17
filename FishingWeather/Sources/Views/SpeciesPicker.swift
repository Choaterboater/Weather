import SwiftUI

/// Horizontal tap-to-pick row of species. Binds to the persisted selection.
struct SpeciesPicker: View {
    @Binding var selection: Species

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Species.allCases) { species in
                    SpeciesChip(species: species, isSelected: species == selection) {
                        withAnimation(.snappy) { selection = species }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct SpeciesChip: View {
    let species: Species
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(species.displayName)
            } icon: {
                Image(systemName: "fish.fill")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .background {
            if isSelected {
                Capsule().fill(species.tint)
            } else {
                Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.0 : 0.96)
        .animation(.snappy(duration: 0.25, extraBounce: 0.1), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(species.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
