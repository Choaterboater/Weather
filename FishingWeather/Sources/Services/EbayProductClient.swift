import Foundation

/// eBay Browse API client. Fetches a client-credentials OAuth token, then returns
/// the top item summary for a query. `init?` fails without credentials, so the
/// feature stays hidden until keys are set.
struct EbayProductClient {
    private let clientID: String
    private let clientSecret: String
    private let campaignID: String?

    init?() {
        guard let clientID = AppSecrets.ebayClientID,
              let clientSecret = AppSecrets.ebayClientSecret else { return nil }
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.campaignID = AppSecrets.ebayCampaignID
    }

    func searchFirst(keywords: String) async throws -> ProductMatch? {
        let token = try await accessToken()

        var components = URLComponents(string: "https://api.ebay.com/buy/browse/v1/item_summary/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: keywords),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("EBAY_US", forHTTPHeaderField: "X-EBAY-C-MARKETPLACE-ID")
        if let campaignID {
            request.setValue("affiliateCampaignId=\(campaignID)", forHTTPHeaderField: "X-EBAY-C-ENDUSERCTX")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard let item = decoded.itemSummaries?.first,
              let imageString = item.image?.imageUrl,
              let imageURL = URL(string: imageString),
              let buyString = item.itemAffiliateWebUrl ?? item.itemWebUrl,
              let buyURL = URL(string: buyString) else {
            return nil
        }
        return ProductMatch(title: item.title ?? keywords, imageURL: imageURL, buyURL: buyURL, retailer: "eBay")
    }

    private func accessToken() async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.ebay.com/identity/v1/oauth2/token")!)
        request.httpMethod = "POST"
        let credentials = Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("grant_type=client_credentials&scope=https://api.ebay.com/oauth/api_scope".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.userAuthenticationRequired)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data).accessToken
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
    }

    private struct SearchResponse: Decodable {
        let itemSummaries: [Item]?

        struct Item: Decodable {
            let title: String?
            let image: ImageRef?
            let itemWebUrl: String?
            let itemAffiliateWebUrl: String?
        }

        struct ImageRef: Decodable {
            let imageUrl: String?
        }
    }
}
