import Foundation

/// Reads secrets without committing them. Each value comes from an Info.plist key
/// (populated from a gitignored xcconfig) or an environment variable for local
/// runs. Anything unset returns nil, and the dependent feature disables cleanly.
enum AppSecrets {
    static var replicateToken: String? {
        value(plistKey: "ReplicateAPIToken", env: "REPLICATE_API_TOKEN")
    }

    static var amazonAccessKey: String? {
        value(plistKey: "AmazonAccessKey", env: "AMAZON_ACCESS_KEY")
    }

    static var amazonSecretKey: String? {
        value(plistKey: "AmazonSecretKey", env: "AMAZON_SECRET_KEY")
    }

    static var amazonPartnerTag: String? {
        value(plistKey: "AmazonPartnerTag", env: "AMAZON_PARTNER_TAG")
    }

    static var ebayClientID: String? {
        value(plistKey: "EbayClientID", env: "EBAY_CLIENT_ID")
    }

    static var ebayClientSecret: String? {
        value(plistKey: "EbayClientSecret", env: "EBAY_CLIENT_SECRET")
    }

    static var ebayCampaignID: String? {
        value(plistKey: "EbayCampaignID", env: "EBAY_CAMPAIGN_ID")
    }

    /// Affiliate-network deep-link template (with a `{url}` placeholder) for the
    /// tackle shops that have no live product API. Amazon/eBay carry affiliate
    /// info in their own product links, so they return nil here.
    static func affiliateTemplate(for retailer: Retailer) -> String? {
        switch retailer {
        case .tackleWarehouse:
            value(plistKey: "TackleWarehouseAffiliateTemplate", env: "TACKLEWAREHOUSE_AFFILIATE_TEMPLATE")
        case .bassPro:
            value(plistKey: "BassProAffiliateTemplate", env: "BASSPRO_AFFILIATE_TEMPLATE")
        case .fishUSA:
            value(plistKey: "FishUSAAffiliateTemplate", env: "FISHUSA_AFFILIATE_TEMPLATE")
        case .amazon, .ebay:
            nil
        }
    }

    private static func value(plistKey: String, env: String) -> String? {
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String,
           !fromPlist.isEmpty, !fromPlist.hasPrefix("$(") {
            return fromPlist
        }
        if let fromEnv = ProcessInfo.processInfo.environment[env], !fromEnv.isEmpty {
            return fromEnv
        }
        return nil
    }
}
