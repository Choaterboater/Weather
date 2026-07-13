import Foundation

enum AppIdentity {
    static let name = "BiteCast"
    static let canonicalContactURL = URL(
        string: "https://github.com/Choaterboater/Weather"
    )!

    static var semanticVersion: String {
        let value = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        return normalizedVersion(value)
    }

    static var userAgent: String {
        userAgent(version: semanticVersion)
    }

    static func userAgent(version: String) -> String {
        "\(name)/\(normalizedVersion(version)) (+\(canonicalContactURL.absoluteString))"
    }

    private static func normalizedVersion(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let semanticVersionPattern = #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*))?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$"#
        guard !trimmed.isEmpty,
              trimmed.range(
                of: semanticVersionPattern,
                options: .regularExpression
              ) == trimmed.startIndex..<trimmed.endIndex
        else { return "0.1.0" }
        return trimmed
    }
}
