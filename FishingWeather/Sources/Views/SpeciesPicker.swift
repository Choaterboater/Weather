import SwiftUI

/// Horizontal tap-to-pick row of species. Binds to the persisted selection.
/// When the active spot has a water type, only matching species (plus All) are shown.
struct SpeciesPicker: View {
    @Binding var selection: Species
    var waterType: WaterType? = nil

    private var choices: [Species] {
        Species.allCases.filter { $0 == .all || $0.isAvailable(for: waterType) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(choices) { species in
                    SpeciesChip(species: species, isSelected: species == selection) {
                        withAnimation(.snappy) { selection = species }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .onChange(of: waterType) {
            // Drop a saltwater focus when the angler switches to a freshwater spot.
            if !choices.contains(selection) {
                selection = .all
            }
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
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? .white : Ink.chartDim)
        }
        // Glass must wrap the label directly: a glassEffect on a .background
        // shape gets hoisted into the enclosing GlassEffectContainer's layer
        // and composites OVER the text, leaving it illegible.
        // Selection uses the app's brass accent (not the per-species tint) so
        // the picker matches every other selected control; species color-coding
        // still lives in the dots/icons in lists and detail views.
        .glassEffect(
            isSelected ? .regular.tint(Ink.brass).interactive() : .regular.interactive(),
            in: .capsule
        )
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.0 : 0.96)
        .animation(.snappy(duration: 0.25, extraBounce: 0.1), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(species.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
