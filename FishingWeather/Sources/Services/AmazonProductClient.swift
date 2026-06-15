import CryptoKit
import Foundation

/// A product hit from a retailer: a real photo plus a buy link.
struct ProductMatch {
    let title: String
    let imageURL: URL
    let buyURL: URL
    let retailer: String
}

/// Amazon Product Advertising API 5.0 client (SearchItems), signed with AWS
/// Signature V4. Returns the top sporting-goods match for a set of keywords.
/// `init?` fails when credentials aren't configured, so the feature stays hidden.
struct AmazonProductClient {
    private let accessKey: String
    private let secretKey: String
    private let partnerTag: String

    private let host = "webservices.amazon.com"
    private let region = "us-east-1"
    private let service = "ProductAdvertisingAPI"
    private let marketplace = "www.amazon.com"

    init?() {
        guard let accessKey = AppSecrets.amazonAccessKey,
              let secretKey = AppSecrets.amazonSecretKey,
              let partnerTag = AppSecrets.amazonPartnerTag else { return nil }
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.partnerTag = partnerTag
    }

    func searchFirst(keywords: String) async throws -> ProductMatch? {
        let path = "/paapi5/searchitems"
        let target = "com.amazon.paapi5.v1.ProductAdvertisingAPIv1.SearchItems"

        let payload: [String: Any] = [
            "Keywords": keywords,
            "SearchIndex": "SportingGoods",
            "ItemCount": 1,
            "PartnerTag": partnerTag,
            "PartnerType": "Associates",
            "Marketplace": marketplace,
            "Resources": ["Images.Primary.Large", "ItemInfo.Title"]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        let (amzDate, dateStamp) = Self.timestamps(for: Date())
        let payloadHash = Self.sha256Hex(body)

        // --- Canonical request (SigV4) ---
        let canonicalHeaders =
            "content-encoding:amz-1.0\n" +
            "host:\(host)\n" +
            "x-amz-date:\(amzDate)\n" +
            "x-amz-target:\(target)\n"
        let signedHeaders = "content-encoding;host;x-amz-date;x-amz-target"
        let canonicalRequest = [
            "POST", path, "", canonicalHeaders, signedHeaders, payloadHash
        ].joined(separator: "\n")

        // --- String to sign ---
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            algorithm,
            amzDate,
            credentialScope,
            Self.sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        // --- Signature ---
        let signingKey = Self.signingKey(secretKey: secretKey, dateStamp: dateStamp, region: region, service: service)
        let signature = Self.hmacHex(key: signingKey, data: Data(stringToSign.utf8))
        let authorization = "\(algorithm) Credential=\(accessKey)/\(credentialScope), "
            + "SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var request = URLRequest(url: URL(string: "https://\(host)\(path)")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("amz-1.0", forHTTPHeaderField: "Content-Encoding")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        request.setValue(target, forHTTPHeaderField: "X-Amz-Target")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard let item = decoded.searchResult?.items?.first,
              let imageString = item.images?.primary?.large?.url,
              let imageURL = URL(string: imageString),
              let buyURL = URL(string: item.detailPageURL) else {
            return nil
        }
        let title = item.itemInfo?.title?.displayValue ?? keywords
        return ProductMatch(title: title, imageURL: imageURL, buyURL: buyURL, retailer: "Amazon")
    }

    // MARK: - Signing helpers

    private static func timestamps(for date: Date) -> (amzDate: String, dateStamp: String) {
        let amz = DateFormatter()
        amz.locale = Locale(identifier: "en_US_POSIX")
        amz.timeZone = TimeZone(identifier: "UTC")
        amz.dateFormat = "yyyyMMdd'T'HHmmss'Z'"

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = TimeZone(identifier: "UTC")
        stamp.dateFormat = "yyyyMMdd"

        return (amz.string(from: date), stamp.string(from: date))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmac(key: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    private static func hmacHex(key: Data, data: Data) -> String {
        hmac(key: key, data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func signingKey(secretKey: String, dateStamp: String, region: String, service: String) -> Data {
        let kDate = hmac(key: Data("AWS4\(secretKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmac(key: kDate, data: Data(region.utf8))
        let kService = hmac(key: kRegion, data: Data(service.utf8))
        return hmac(key: kService, data: Data("aws4_request".utf8))
    }

    // MARK: - Response

    private struct SearchResponse: Decodable {
        let searchResult: SearchResult?
        enum CodingKeys: String, CodingKey { case searchResult = "SearchResult" }

        struct SearchResult: Decodable {
            let items: [Item]?
            enum CodingKeys: String, CodingKey { case items = "Items" }
        }

        struct Item: Decodable {
            let detailPageURL: String
            let images: Images?
            let itemInfo: ItemInfo?
            enum CodingKeys: String, CodingKey {
                case detailPageURL = "DetailPageURL"
                case images = "Images"
                case itemInfo = "ItemInfo"
            }
        }

        struct Images: Decodable {
            let primary: Primary?
            enum CodingKeys: String, CodingKey { case primary = "Primary" }
        }

        struct Primary: Decodable {
            let large: ImageSize?
            enum CodingKeys: String, CodingKey { case large = "Large" }
        }

        struct ImageSize: Decodable {
            let url: String?
            enum CodingKeys: String, CodingKey { case url = "URL" }
        }

        struct ItemInfo: Decodable {
            let title: TitleField?
            enum CodingKeys: String, CodingKey { case title = "Title" }
        }

        struct TitleField: Decodable {
            let displayValue: String?
            enum CodingKeys: String, CodingKey { case displayValue = "DisplayValue" }
        }
    }
}
