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
    private var loadID = 0

    func load(recommendation: BaitRecommendation, species: Species, preferred: Retailer, key: String) async {
        loadID += 1
        let id = loadID

        if let cached = cache[key] {
            state = .loaded(cached)
            return
        }
        state = .loading
        let image = await BaitImageService.firstImage(for: recommendation, species: species, preferred: preferred)
        // A newer key superseded us (or `.task(id:)` cancelled). Providers can
        // also swallow cancellation as nil — never clobber the active load.
        guard id == loadID, !Task.isCancelled else { return }
        if let image {
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
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
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
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
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
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Ink.chartDim)
                    .accessibilityHint("Change preferred store")
            }
        }
        .sensoryFeedback(.selection, trigger: preferredRetailerRaw)
    }

    private func artImage(_ image: BaitImage) -> some View {
        AsyncImage(url: image.url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
            case .failure:
                placeholder.overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(Ink.chartDim.opacity(0.5))
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
        LinearGradient(
            colors: [Ink.hullLine.opacity(0.3), Ink.abyss.opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 170)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Ink.hullLine, lineWidth: 1)
        )
    }
}
