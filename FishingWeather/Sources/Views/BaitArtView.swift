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

    func load(recommendation: BaitRecommendation, species: Species, key: String) async {
        if let cached = cache[key] {
            state = .loaded(cached)
            return
        }
        state = .loading
        if let image = await BaitImageService.firstImage(for: recommendation, species: species) {
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

    @State private var loader = BaitArtLoader()

    private var cacheKey: String {
        "\(species.rawValue)|\(recommendation.topBait)|\(recommendation.color)"
    }

    var body: some View {
        content
            .task(id: cacheKey) {
                await loader.load(recommendation: recommendation, species: species, key: cacheKey)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch loader.state {
        case .idle, .loading:
            placeholder.overlay { ProgressView() }
        case .loaded(let image):
            VStack(alignment: .leading, spacing: 6) {
                artImage(image)
                if let caption = image.caption {
                    if let buyURL = image.buyURL {
                        Link(destination: buyURL) {
                            Label(caption, systemImage: "bag")
                                .font(.caption)
                                .lineLimit(1)
                        }
                    } else {
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .hidden:
            EmptyView()
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
