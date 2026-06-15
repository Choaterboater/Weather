import SwiftUI

/// Loads (and caches) Replicate-generated art for a bait recommendation.
@MainActor
@Observable
final class BaitArtLoader {
    enum State {
        case idle, loading, loaded(URL), hidden
    }

    private(set) var state: State = .idle
    private var cache: [String: URL] = [:]

    func load(prompt: String, key: String) async {
        if let cached = cache[key] {
            state = .loaded(cached)
            return
        }
        guard let client = ReplicateClient() else {
            state = .hidden // no token — feature off
            return
        }
        state = .loading
        do {
            let url = try await client.image(prompt: prompt)
            cache[key] = url
            state = .loaded(url)
        } catch {
            state = .hidden // fail quietly; the text recommendation still stands
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

    private var prompt: String {
        "Detailed product illustration of a \(recommendation.color) \(recommendation.topBait) "
        + "fishing lure for \(species.promptName), studio lighting, clean neutral background"
    }

    var body: some View {
        content
            .task(id: cacheKey) { await loader.load(prompt: prompt, key: cacheKey) }
    }

    @ViewBuilder
    private var content: some View {
        switch loader.state {
        case .idle, .loading:
            placeholder.overlay { ProgressView() }
        case .loaded(let url):
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder.overlay { ProgressView() }
            }
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 16))
        case .hidden:
            EmptyView()
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.quaternary)
            .frame(height: 160)
            .frame(maxWidth: .infinity)
    }
}
