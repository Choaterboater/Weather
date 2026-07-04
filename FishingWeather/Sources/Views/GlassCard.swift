import SwiftUI

/// A reusable Liquid Glass container card. Wraps content in padding and applies
/// the system glass effect with a rounded-rectangle shape.
struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .scrollTransition { view, phase in
                view
                    .opacity(phase.isIdentity ? 1 : 0.5)
                    .scaleEffect(phase.isIdentity ? 1 : 0.96)
            }
    }
}

/// Wraps a screen's card stack in a GlassEffectContainer so sibling glass
/// shapes blend/morph correctly and never sample each other. Glass cannot
/// sample glass, so this must wrap SIBLING cards — it can't live inside
/// GlassCard itself.
struct GlassCardStack<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            VStack(spacing: spacing) { content }
        }
    }
}

/// Small labeled section header used above each card.
struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(.headline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}
