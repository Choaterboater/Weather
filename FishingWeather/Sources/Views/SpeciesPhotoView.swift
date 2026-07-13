import SwiftUI

/// Renders a manifest-approved species photo or a BiteCast-owned field-guide
/// illustration. The illustration is intentional product art, not a missing
/// image placeholder, and remains the default until photo provenance is proven.
struct SpeciesPhotoView: View {
    enum Size: CaseIterable, Equatable, Sendable { case card, hero, square }

    let species: Species
    var size: Size = .card
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var presentation: SpeciesPhotoPresentation {
        SpeciesPhotoPresentation(
            size: size,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
    }

    var body: some View {
        Group {
            if let media = species.bundledMedia,
               UIImage(named: media.assetName) != nil {
                Image(media.assetName)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel(
                        "Photo of \(species.displayName). \(media.attribution)"
                    )
            } else {
                fieldGuideIllustration
            }
        }
        .clipped()
    }

    private var fieldGuideIllustration: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.11, blue: 0.16),
                    species.tint.opacity(0.62),
                    Color(red: 0.015, green: 0.06, blue: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            MarineTexture(tint: species.tint)
                .opacity(0.34)
                .accessibilityHidden(true)

            RadialGradient(
                colors: [.white.opacity(0.16), .clear],
                center: .center,
                startRadius: 2,
                endRadius: size == .hero ? 150 : 90
            )

            fishEmblem
                .offset(x: emblemOffset.width, y: emblemOffset.height)

            speciesIdentity
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(identityPadding)

            fieldGuideBadge
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: presentation.ownershipStyle == .sealOnly
                        ? .topTrailing
                        : .topLeading
                )
                .padding(size == .hero ? 16 : 9)
        }
        .overlay {
            RoundedRectangle(cornerRadius: size == .hero ? 20 : 14)
                .strokeBorder(.white.opacity(0.13), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(species.mediaAccessibilityLabel)
    }

    private var fishEmblem: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.2))
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.19), lineWidth: 1)
                }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.2), species.tint.opacity(0.08)],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: emblemSize * 0.7
                    )
                )
                .padding(emblemSize * 0.09)

            Image(systemName: "fish.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white.opacity(0.95), species.tint.opacity(0.92))
                .shadow(color: .black.opacity(0.3), radius: 9, y: 6)
        }
        .frame(width: emblemSize, height: emblemSize)
        .accessibilityHidden(true)
    }

    private var fieldGuideBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(species.tint, .white.opacity(0.9))
            if presentation.ownershipStyle == .wordmark {
                Text("BiteCast original")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, size == .hero ? 10 : 7)
        .padding(.vertical, size == .hero ? 7 : 5)
        .background(.black.opacity(0.28), in: .capsule)
        .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1) }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel("BiteCast original artwork")
    }

    private var speciesIdentity: some View {
        VStack(alignment: .leading, spacing: presentation.identityStyle == .compact ? 1 : 3) {
            if presentation.showsDisplayName {
                Text(species.displayName)
                    .font(identityTitleFont)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(presentation.identityLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if presentation.showsScientificName,
               let scientificName = species.scientificName {
                Text(scientificName)
                    .font(identityScientificFont)
                    .italic()
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(presentation.identityLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: identityMaximumWidth, alignment: .leading)
        .padding(.horizontal, presentation.identityStyle == .compact ? 6 : 9)
        .padding(.vertical, presentation.identityStyle == .compact ? 4 : 7)
        .background(.black.opacity(0.38), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .dynamicTypeSize(...presentation.maximumIdentityDynamicTypeSize)
        .accessibilityHidden(true)
    }

    private var identityTitleFont: Font {
        switch size {
        case .hero: .system(.title3, design: .rounded)
        case .card: .system(.caption, design: .rounded)
        case .square: .system(.caption2, design: .rounded)
        }
    }

    private var identityScientificFont: Font {
        switch size {
        case .hero: .system(.subheadline, design: .rounded)
        case .card: .system(.caption2, design: .rounded)
        case .square: .system(.caption2, design: .rounded)
        }
    }

    private var identityMaximumWidth: CGFloat {
        switch size {
        case .hero: 245
        case .card: 118
        case .square: 82
        }
    }

    private var identityPadding: CGFloat {
        switch size {
        case .hero: 16
        case .card: 9
        case .square: 6
        }
    }

    private var emblemOffset: CGSize {
        switch size {
        case .hero: CGSize(width: 52, height: -2)
        case .card: CGSize(width: 28, height: -10)
        case .square: CGSize(width: 14, height: -12)
        }
    }

    private var iconSize: CGFloat {
        switch size {
        case .card: 52
        case .hero: 90
        case .square: 24
        }
    }

    private var emblemSize: CGFloat {
        switch size {
        case .card: 82
        case .hero: 150
        case .square: 38
        }
    }
}

/// A testable presentation contract for the fallback art. Large Dynamic Type
/// swaps the ownership wordmark for its seal and keeps the species identity
/// multiline; it never shrinks a one-line label until it fits.
struct SpeciesPhotoPresentation: Equatable {
    enum IdentityStyle: Equatable {
        case regular
        case compact
    }

    enum OwnershipStyle: Equatable {
        case wordmark
        case sealOnly
    }

    let identityStyle: IdentityStyle
    let ownershipStyle: OwnershipStyle
    let identityLineLimit: Int?
    let maximumIdentityDynamicTypeSize: DynamicTypeSize
    let showsDisplayName: Bool
    let showsScientificName: Bool
    let usesAccessibilityLayout: Bool

    init(size: SpeciesPhotoView.Size, isAccessibilitySize: Bool) {
        identityStyle = size == .square ? .compact : .regular
        ownershipStyle = isAccessibilitySize || size == .square ? .sealOnly : .wordmark
        identityLineLimit = nil
        showsDisplayName = true
        showsScientificName = true
        usesAccessibilityLayout = isAccessibilitySize

        switch size {
        case .hero:
            maximumIdentityDynamicTypeSize = .accessibility1
        case .card:
            maximumIdentityDynamicTypeSize = .xxxLarge
        case .square:
            maximumIdentityDynamicTypeSize = .xxLarge
        }
    }
}

private struct MarineTexture: View {
    let tint: Color

    var body: some View {
        Canvas { context, size in
            for row in 0..<7 {
                let baseline = size.height * (0.18 + CGFloat(row) * 0.13)
                var wave = Path()
                wave.move(to: CGPoint(x: -20, y: baseline))
                for column in 0..<6 {
                    let start = CGFloat(column) * size.width / 5 - 20
                    let width = size.width / 5
                    wave.addCurve(
                        to: CGPoint(x: start + width, y: baseline),
                        control1: CGPoint(x: start + width * 0.25, y: baseline - 10),
                        control2: CGPoint(x: start + width * 0.75, y: baseline + 10)
                    )
                }
                context.stroke(
                    wave,
                    with: .color(.white.opacity(row.isMultiple(of: 2) ? 0.17 : 0.09)),
                    lineWidth: 1
                )
            }

            let bubblePoints: [CGPoint] = [
                CGPoint(x: size.width * 0.78, y: size.height * 0.18),
                CGPoint(x: size.width * 0.86, y: size.height * 0.29),
                CGPoint(x: size.width * 0.72, y: size.height * 0.34),
            ]
            for (index, point) in bubblePoints.enumerated() {
                let diameter = CGFloat(5 + index * 3)
                context.stroke(
                    Path(ellipseIn: CGRect(
                        x: point.x,
                        y: point.y,
                        width: diameter,
                        height: diameter
                    )),
                    with: .color(tint.opacity(0.74)),
                    lineWidth: 1.5
                )
            }
        }
        .allowsHitTesting(false)
    }
}
