import Foundation

/// Reads secrets without committing them. The Replicate token comes from the
/// `ReplicateAPIToken` Info.plist key (populated from a gitignored xcconfig) or
/// the `REPLICATE_API_TOKEN` environment variable for local runs. When unset,
/// image generation is simply disabled.
enum AppSecrets {
    static var replicateToken: String? {
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "ReplicateAPIToken") as? String,
           !fromPlist.isEmpty, !fromPlist.hasPrefix("$(") {
            return fromPlist
        }
        if let env = ProcessInfo.processInfo.environment["REPLICATE_API_TOKEN"], !env.isEmpty {
            return env
        }
        return nil
    }
}
