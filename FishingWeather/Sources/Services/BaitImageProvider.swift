import Foundation

/// An image to show on the bait card. Real products carry a `buyURL` and the
/// `sourceRetailer` they came from; AI-generated art does not.
struct BaitImage {
    let url: URL
    let buyURL: URL?
    let caption: String?
    let sourceRetailer: Retailer?
    let isGenerated: Bool
}

/// A source of bait imagery. New retailers slot in by conforming another type and
/// adding it to the chain.
protocol BaitImageProvider: Sendable {
    func image(for recommendation: BaitRecommendation, species: Species) async -> BaitImage?
}

private func keywords(for recommendation: BaitRecommendation) -> String {
    "\(recommendation.color) \(recommendation.topBait) fishing lure"
}

/// Real product photo + buy link from Amazon's Product Advertising API.
struct AmazonBaitImageProvider: BaitImageProvider {
    private let client: AmazonProductClient

    init?() {
        guard let client = AmazonProductClient() else { return nil }
        self.client = client
    }

    func image(for recommendation: BaitRecommendation, species: Species) async -> BaitImage? {
        guard let match = try? await client.searchFirst(keywords: keywords(for: recommendation)) else { return nil }
        return BaitImage(
            url: match.imageURL,
            buyURL: match.buyURL,
            caption: "\(match.title) · \(match.retailer)",
            sourceRetailer: .amazon,
            isGenerated: false
        )
    }
}

/// Real product photo + buy link from the eBay Browse API.
struct EbayBaitImageProvider: BaitImageProvider {
    private let client: EbayProductClient

    init?() {
        guard let client = EbayProductClient() else { return nil }
        self.client = client
    }

    func image(for recommendation: BaitRecommendation, species: Species) async -> BaitImage? {
        guard let match = try? await client.searchFirst(keywords: keywords(for: recommendation)) else { return nil }
        return BaitImage(
            url: match.imageURL,
            buyURL: match.buyURL,
            caption: "\(match.title) · \(match.retailer)",
            sourceRetailer: .ebay,
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
        return BaitImage(url: url, buyURL: nil, caption: "AI-generated", sourceRetailer: nil, isGenerated: true)
    }
}

/// Tries each configured provider in order and returns the first image. Photo
/// retailers (Amazon, eBay) win; generated art is last. Photo source order
/// follows the angler's preferred store when it serves photos.
enum BaitImageService {
    static func providers(preferred: Retailer) -> [BaitImageProvider] {
        var providers: [BaitImageProvider] = []

        let amazon = AmazonBaitImageProvider()
        let ebay = EbayBaitImageProvider()

        // Put the preferred photo retailer first.
        if preferred == .ebay {
            if let ebay { providers.append(ebay) }
            if let amazon { providers.append(amazon) }
        } else {
            if let amazon { providers.append(amazon) }
            if let ebay { providers.append(ebay) }
        }

        if let replicate = ReplicateBaitImageProvider() { providers.append(replicate) }
        return providers
    }

    static func firstImage(
        for recommendation: BaitRecommendation,
        species: Species,
        preferred: Retailer
    ) async -> BaitImage? {
        for provider in providers(preferred: preferred) {
            if let image = await provider.image(for: recommendation, species: species) {
                return image
            }
        }
        return nil
    }
}
