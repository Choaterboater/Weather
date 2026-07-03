import Foundation

/// A storefront the angler can shop a recommended bait at. Amazon and eBay also
/// serve product photos (see their providers); the rest are reachable via a
/// search link, optionally wrapped by an affiliate-network deep link later.
enum Retailer: String, CaseIterable, Identifiable {
    case amazon
    case ebay
    case tackleWarehouse
    case bassPro
    case fishUSA

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .amazon: "Amazon"
        case .ebay: "eBay"
        case .tackleWarehouse: "Tackle Warehouse"
        case .bassPro: "Bass Pro Shops"
        case .fishUSA: "FishUSA"
        }
    }

    /// Whether this retailer can return a real product photo (has a live API).
    var servesPhotos: Bool {
        self == .amazon || self == .ebay
    }

    /// The link to open when shopping a bait: the store search, wrapped in an
    /// affiliate-network deep link when one is configured for this retailer.
    func shopURL(for query: String) -> URL? {
        guard let raw = searchURL(for: query) else { return nil }
        if let template = AppSecrets.affiliateTemplate(for: self),
           let wrapped = AffiliateLinkBuilder.wrap(raw, template: template) {
            return wrapped
        }
        return raw
    }

    /// The raw store search URL for the query, with an affiliate tag appended
    /// where we model one inline (Amazon, eBay). Built via `URLComponents` —
    /// AI-generated bait names contain "&" ("Salt & Pepper grub"), which
    /// `.urlQueryAllowed` leaves unescaped, corrupting the query. URLs for the
    /// tackle shops are best-effort and easy to adjust if a site changes its
    /// search path.
    func searchURL(for query: String) -> URL? {
        var components: URLComponents?
        var items: [URLQueryItem] = []
        switch self {
        case .amazon:
            components = URLComponents(string: "https://www.amazon.com/s")
            items = [URLQueryItem(name: "k", value: query)]
            if let tag = AppSecrets.amazonPartnerTag {
                items.append(URLQueryItem(name: "tag", value: tag))
            }
        case .ebay:
            components = URLComponents(string: "https://www.ebay.com/sch/i.html")
            items = [URLQueryItem(name: "_nkw", value: query)]
            if let campaign = AppSecrets.ebayCampaignID {
                items.append(URLQueryItem(name: "mkcid", value: "1"))
                items.append(URLQueryItem(name: "campid", value: campaign))
            }
        case .tackleWarehouse:
            components = URLComponents(string: "https://www.tacklewarehouse.com/search.html")
            items = [URLQueryItem(name: "keyword", value: query)]
        case .bassPro:
            components = URLComponents(string: "https://www.basspro.com/shop/SearchDisplay")
            items = [URLQueryItem(name: "searchTerm", value: query)]
        case .fishUSA:
            components = URLComponents(string: "https://www.fishusa.com/search")
            items = [URLQueryItem(name: "q", value: query)]
        }
        components?.queryItems = items
        return components?.url
    }
}
