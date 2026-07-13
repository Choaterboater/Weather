import Foundation

enum LegalDocument: String, CaseIterable, Identifiable, Sendable {
    case privacy
    case terms
    case support
    case thirdParty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "Privacy"
        case .terms: "Terms of Use"
        case .support: "Support"
        case .thirdParty: "Third-Party Notices"
        }
    }

    var summary: String {
        switch self {
        case .privacy: "Location, catches, photos, services, and deletion"
        case .terms: "Safety, regulations, AI, and responsible use"
        case .support: "Troubleshooting, privacy-safe reports, and data removal"
        case .thirdParty: "Weather, maps, water data, media, and external services"
        }
    }

    var systemImage: String {
        switch self {
        case .privacy: "hand.raised.fill"
        case .terms: "doc.text.fill"
        case .support: "lifepreserver.fill"
        case .thirdParty: "shippingbox.fill"
        }
    }

    var resourceName: String {
        switch self {
        case .privacy: "Privacy"
        case .terms: "Terms"
        case .support: "Support"
        case .thirdParty: "ThirdPartyNotices"
        }
    }

    var accessibilityIdentifier: String {
        "legal.document.\(rawValue)"
    }

    var externalURL: URL? {
        guard self == .support else { return nil }
        return URL(string: "https://github.com/Choaterboater/Weather")
    }

}

enum LegalDocumentError: LocalizedError, Equatable {
    case missingResource(String)
    case emptyResource(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            "The bundled \(name) document is unavailable."
        case .emptyResource(let name):
            "The bundled \(name) document is empty."
        }
    }
}

struct LegalDocumentBody: Equatable, Sendable {
    enum Block: Equatable, Sendable {
        case text(String)
        case link(URL)
    }

    let blocks: [Block]

    init(text: String) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        blocks = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { block in
                if let url = URL(string: block),
                   url.scheme?.lowercased() == "https",
                   !(url.host?.isEmpty ?? true),
                   !block.contains("\n") {
                    return .link(url)
                }
                return .text(block)
            }
    }
}
