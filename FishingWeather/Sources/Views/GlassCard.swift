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
