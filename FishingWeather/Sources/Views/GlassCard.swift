import SwiftUI

/// A calm content card. Liquid Glass is intentionally reserved for floating
/// controls and selected chips rather than applied to every scrolling surface.
struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.card.opacity(0.96), in: .rect(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Ink.hullLine.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }
}

/// Keeps legacy call sites consistently spaced. `mergeSpacing` remains source
/// compatible but no longer merges card surfaces into a global glass layer.
struct GlassCardStack<Content: View>: View {
    var spacing: CGFloat = 20
    /// Retained for source compatibility with pre-shell call sites. Card
    /// surfaces no longer merge, so this value has no visual effect.
    var mergeSpacing: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: spacing) { content }
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
        .font(.system(.subheadline, design: .rounded, weight: .semibold))
        .foregroundStyle(Ink.chartDim)
        .padding(.horizontal, 4)
    }
}
