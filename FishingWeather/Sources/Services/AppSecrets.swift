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
