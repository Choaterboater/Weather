import Foundation

/// An image to show on the bait card. Real products carry a `buyURL` and source
/// retailer; AI-generated art does not.
struct BaitImage {
    let url: URL
    let buyURL: URL?
    let caption: String?
    let isGenerated: Bool
}

/// A source of bait imagery. New retailers (Tackle Warehouse, Bass Pro, FishUSA,
/// etc.) can be added by conforming another type and dropping it into the chain.
protocol BaitImageProvider: Sendable {
    func image(for recommendation: BaitRecommendation, species: Species) async -> BaitImage?
}

/// Real product photo + buy link from Amazon's Product Advertising API.
struct AmazonBaitImageProvider: BaitImageProvider {
    private let client: AmazonProductClient

    init?() {
        guard let client = AmazonProductClient() else { return nil }
        self.client = client
    }

    func image(for recommendation: BaitRecommendation, species: Species) async -> BaitImage? {
        let keywords = "\(recommendation.color) \(recommendation.topBait) fishing lure"
        guard let match = try? await client.searchFirst(keywords: keywords) else { return nil }
        return BaitImage(
            url: match.imageURL,
            buyURL: match.buyURL,
            caption: "\(match.title) · \(match.retailer)",
            isGenerated: false
        )
    }
}

/// AI-generated lure art via Replicate — the fallback when no product matches.
struct ReplicateBaitImageProvider: BaitImageProvider {
    private let client: ReplicateClient

    init?() {
        guard let client = ReplicateClient() else { return nil }
        self.client = client
    }

    func image(for recommendation: BaitRecommendation, species: Species) async -> BaitImage? {
        let prompt = "Detailed product illustration of a \(recommendation.color) "
            + "\(recommendation.topBait) fishing lure for \(species.promptName), "
            + "studio lighting, clean neutral background"
        guard let url = try? await client.image(prompt: prompt) else { return nil }
        return BaitImage(url: url, buyURL: nil, caption: "AI-generated", isGenerated: true)
    }
}

/// Tries each configured provider in order and returns the first image.
/// Real products (Amazon, then any tackle retailers) win; generated art is last.
enum BaitImageService {
    static func providers() -> [BaitImageProvider] {
        var providers: [BaitImageProvider] = []
        if let amazon = AmazonBaitImageProvider() { providers.append(amazon) }
        // Add tackle-retailer providers here as they come online.
        if let replicate = ReplicateBaitImageProvider() { providers.append(replicate) }
        return providers
    }

    static func firstImage(for recommendation: BaitRecommendation, species: Species) async -> BaitImage? {
        for provider in providers() {
            if let image = await provider.image(for: recommendation, species: species) {
                return image
            }
        }
        return nil
    }
}
