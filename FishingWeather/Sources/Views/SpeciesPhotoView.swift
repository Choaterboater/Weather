import SwiftUI

/// Renders a fish photo for a Species. Uses the bundled Asset Catalog image
/// (CC-licensed photo from iNaturalist) and falls back to a tinted SF Symbol
/// silhouette when no image is available (e.g. `.all`).
struct SpeciesPhotoView: View {
    enum Size { case card, hero, square }

    let species: Species
    var size: Size = .card

    var body: some View {
        Group {
            if UIImage(named: species.rawValue) != nil {
                Image(species.rawValue)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback
            }
        }
        .clipped()
    }

    private var fallback: some View {
        LinearGradient(
            colors: [species.tint.opacity(0.35), species.tint.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .center) {
            Image(systemName: "fish.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(species.tint)
        }
    }

    private var iconSize: CGFloat {
        switch size {
        case .card: 36
        case .hero: 42
        case .square: 22
        }
    }
}
