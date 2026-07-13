import Foundation

/// Complete provenance for a bundled species image. BiteCast deliberately
/// accepts only a narrow set of commercial-safe licenses; anything malformed,
/// incomplete, or outside the allowlist is treated as unavailable.
struct SpeciesMediaLicense: Codable, Equatable, Sendable {
    enum ValidationIssue: String, Hashable, Sendable {
        case missingAssetName
        case missingCreator
        case invalidSourceURL
        case unsupportedLicense
        case invalidLicenseURL
        case missingModificationNote
        case invalidProofURL
    }

    let species: Species
    let assetName: String
    let creator: String
    let sourceURL: URL
    let licenseIdentifier: String
    let licenseVersion: String
    let licenseURL: URL
    let modificationNote: String
    let proofURL: URL

    var validationIssues: Set<ValidationIssue> {
        var issues: Set<ValidationIssue> = []
        if assetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.insert(.missingAssetName)
        }
        if creator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.insert(.missingCreator)
        }
        if !Self.isSecureWebURL(sourceURL) {
            issues.insert(.invalidSourceURL)
        }
        if !Self.isSupportedLicense(identifier: licenseIdentifier, version: licenseVersion) {
            issues.insert(.unsupportedLicense)
        }
        if !Self.isExpectedLicenseURL(
            licenseURL,
            identifier: licenseIdentifier,
            version: licenseVersion
        ) {
            issues.insert(.invalidLicenseURL)
        }
        if modificationNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.insert(.missingModificationNote)
        }
        if !Self.isSecureWebURL(proofURL) {
            issues.insert(.invalidProofURL)
        }
        return issues
    }

    var isApproved: Bool { validationIssues.isEmpty && species != .all }

    var attribution: String {
        "\(creator.trimmingCharacters(in: .whitespacesAndNewlines)) · "
            + "\(Self.normalizedIdentifier(licenseIdentifier)) "
            + licenseVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSupportedLicense(identifier: String, version: String) -> Bool {
        let license = normalizedIdentifier(identifier)
        let version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch (license, version) {
        case ("CC0", "1.0"), ("PDM", "1.0"), ("CC-BY", "3.0"), ("CC-BY", "4.0"):
            true
        default:
            false
        }
    }

    private static func isExpectedLicenseURL(
        _ url: URL,
        identifier: String,
        version: String
    ) -> Bool {
        guard isSecureWebURL(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.lowercased() == "creativecommons.org",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil else {
            return false
        }

        let version = version.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let canonicalPath: String
        switch normalizedIdentifier(identifier) {
        case "CC0":
            canonicalPath = "/publicdomain/zero/\(version)"
        case "PDM":
            canonicalPath = "/publicdomain/mark/\(version)"
        case "CC-BY":
            canonicalPath = "/licenses/by/\(version)"
        default:
            return false
        }

        let legalCodePath = canonicalPath + "/legalcode"
        return components.percentEncodedPath == canonicalPath
            || components.percentEncodedPath == canonicalPath + "/"
            || components.percentEncodedPath == legalCodePath
            || components.percentEncodedPath == legalCodePath + "/"
    }

    private static func isSecureWebURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme?.lowercased() == "https"
            && !(components.host?.isEmpty ?? true)
    }

    private static func normalizedIdentifier(_ identifier: String) -> String {
        identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}

struct SpeciesMediaManifest: Codable, Equatable, Sendable {
    let entries: [SpeciesMediaLicense]

    /// Decodes an all-or-nothing manifest. One invalid entry, duplicate species,
    /// or duplicate asset invalidates the entire catalog instead of allowing a
    /// partially trusted set to ship.
    static func approvedEntries(from data: Data) -> [Species: SpeciesMediaLicense] {
        guard let manifest = try? JSONDecoder().decode(Self.self, from: data),
              manifest.entries.allSatisfy(\.isApproved) else { return [:] }

        let species = manifest.entries.map(\.species)
        let assets = manifest.entries.map(\.assetName)
        guard Set(species).count == species.count,
              Set(assets).count == assets.count else { return [:] }

        return Dictionary(uniqueKeysWithValues: manifest.entries.map { ($0.species, $0) })
    }
}

enum SpeciesMediaCatalog {
    static let bundled: [Species: SpeciesMediaLicense] = {
        guard let url = Bundle.main.url(
            forResource: "SpeciesMediaLicenses",
            withExtension: "json"
        ), let data = try? Data(contentsOf: url) else { return [:] }

        return SpeciesMediaManifest.approvedEntries(from: data)
    }()
}
