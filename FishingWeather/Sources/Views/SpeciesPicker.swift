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
                        selection = species
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Label {
                Text(species.displayName)
            } icon: {
                Image(systemName: "fish.fill")
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .scaleEffect(reduceMotion ? 1 : (isSelected ? 1 : 0.96))
            .animation(
                reduceMotion
                    ? nil
                    : .snappy(duration: 0.25, extraBounce: 0.1),
                value: isSelected
            )
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(isSelected ? .white : Ink.chartDim)
            .contentShape(.capsule)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(species.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
