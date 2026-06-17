import SwiftUI

/// Loads (and caches) a bait image — a real product photo when available,
/// otherwise AI-generated art.
@MainActor
@Observable
final class BaitArtLoader {
    enum State {
        case idle, loading, loaded(BaitImage), hidden
    }

    private(set) var state: State = .idle
    private var cache: [String: BaitImage] = [:]

    func load(recommendation: BaitRecommendation, species: Species, preferred: Retailer, key: String) async {
        if let cached = cache[key] {
            state = .loaded(cached)
            return
        }
        state = .loading
        if let image = await BaitImageService.firstImage(for: recommendation, species: species, preferred: preferred) {
            cache[key] = image
            state = .loaded(image)
        } else {
            state = .hidden // no providers configured, or all failed
        }
    }
}

struct BaitArtView: View {
    let recommendation: BaitRecommendation
    let species: Species

    @AppStorage("preferredRetailer") private var preferredRetailerRaw = Retailer.amazon.rawValue
    @State private var loader = BaitArtLoader()

    private var preferred: Retailer { Retailer(rawValue: preferredRetailerRaw) ?? .amazon }

    private var cacheKey: String {
        // Photo source order depends on the preferred photo retailer.
        let photoPref = preferred.servesPhotos ? preferred.rawValue : "default"
        return "\(photoPref)|\(species.rawValue)|\(recommendation.topBait)|\(recommendation.color)"
    }

    private var shopQuery: String {
        "\(recommendation.color) \(recommendation.topBait) fishing lure"
    }

    var body: some View {
        content
            .task(id: cacheKey) {
                await loader.load(recommendation: recommendation, species: species, preferred: preferred, key: cacheKey)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch loader.state {
        case .idle, .loading:
            placeholder.overlay { ProgressView() }
        case .loaded(let image):
            VStack(alignment: .leading, spacing: 8) {
                artImage(image)
                if let caption = image.caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                shopRow(for: image)
            }
        case .hidden:
            // Even without a photo, still let the angler shop the bait.
            shopRow(for: nil)
        }
    }

    /// "Buy"/"Find" link for the preferred store, plus a menu to switch stores.
    @ViewBuilder
    private func shopRow(for image: BaitImage?) -> some View {
        let exactMatch = image?.sourceRetailer == preferred ? image?.buyURL : nil
        let destination = exactMatch ?? preferred.shopURL(for: shopQuery)

        HStack {
            if let destination {
                Link(destination: destination) {
                    Label(
                        exactMatch != nil ? "Buy on \(preferred.displayName)" : "Find on \(preferred.displayName)",
                        systemImage: "bag"
                    )
                    .font(.caption.weight(.medium))
                }
            }
            Spacer()
            Menu {
                Picker("Store", selection: $preferredRetailerRaw) {
                    ForEach(Retailer.allCases) { retailer in
                        Text(retailer.displayName).tag(retailer.rawValue)
                    }
                }
            } label: {
                Label("Store", systemImage: "cart")
                    .font(.caption)
                    .accessibilityHint("Change preferred store")
            }
        }
    }

    private func artImage(_ image: BaitImage) -> some View {
        AsyncImage(url: image.url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
            case .failure:
                placeholder.overlay {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            default:
                placeholder.overlay { ProgressView() }
            }
        }
        .frame(height: 170)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 16))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.quaternary)
            .frame(height: 170)
            .frame(maxWidth: .infinity)
    }
}
