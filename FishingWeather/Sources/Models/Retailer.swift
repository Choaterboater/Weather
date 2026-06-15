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

    /// A search URL on the retailer for the query, with an affiliate tag appended
    /// where we model one. URLs for the tackle shops are best-effort and easy to
    /// adjust if a site changes its search path.
    func searchURL(for query: String) -> URL? {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch self {
        case .amazon:
            let tag = AppSecrets.amazonPartnerTag.map { "&tag=\($0)" } ?? ""
            return URL(string: "https://www.amazon.com/s?k=\(q)\(tag)")
        case .ebay:
            let campaign = AppSecrets.ebayCampaignID.map { "&mkcid=1&campid=\($0)" } ?? ""
            return URL(string: "https://www.ebay.com/sch/i.html?_nkw=\(q)\(campaign)")
        case .tackleWarehouse:
            return URL(string: "https://www.tacklewarehouse.com/search.html?keyword=\(q)")
        case .bassPro:
            return URL(string: "https://www.basspro.com/shop/SearchDisplay?searchTerm=\(q)")
        case .fishUSA:
            return URL(string: "https://www.fishusa.com/search?q=\(q)")
        }
    }
}
