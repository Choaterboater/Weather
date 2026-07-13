import Foundation
import SwiftUI
import Testing
@testable import BiteCast

@Suite("Species media licensing")
struct SpeciesMediaLicenseTests {
    @Test
    func unprovenBundledPhotosAreQuarantined() throws {
        let imageSets = try FileManager.default.contentsOfDirectory(
            at: speciesAssetDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "imageset" }

        #expect(imageSets.isEmpty)
        #expect(Species.allCases.allSatisfy { $0.photoCredit == nil })
    }

    @Test
    func commercialAttributionWithCompleteProofIsApproved() {
        let license = makeLicense()
        let legalCode = makeLicense(
            licenseURL: URL(
                string: "https://creativecommons.org/licenses/by/4.0/legalcode"
            )!
        )
        let canonicalWithoutSlash = makeLicense(
            licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0")!
        )
        let legalCodeWithSlash = makeLicense(
            licenseURL: URL(
                string: "https://creativecommons.org/licenses/by/4.0/legalcode/"
            )!
        )

        #expect(license.validationIssues.isEmpty)
        #expect(license.isApproved)
        #expect(legalCode.isApproved)
        #expect(canonicalWithoutSlash.isApproved)
        #expect(legalCodeWithSlash.isApproved)
        #expect(license.attribution == "Jane Angler · CC-BY 4.0")
    }

    @Test(arguments: [
        "https://creativecommons.org/licenses/by/4.0evil/",
        "https://creativecommons.org/licenses/by/4.0/deed.en",
        "https://creativecommons.org/licenses/by/4.0/legalcode/extra",
        "https://creativecommons.org//licenses/by/4.0",
        "https://creativecommons.org///licenses/by/4.0",
        "https://creativecommons.org/licenses//by/4.0",
        "https://creativecommons.org/licenses/by//4.0",
        "https://creativecommons.org/licenses/by/4.0//",
        "https://creativecommons.org/licenses/by/4.0/legalcode//",
        "https://creativecommons.org/LICENSES/BY/4.0",
        "https://creativecommons.org/licenses/BY/4.0",
        "https://creativecommons.org/licenses/by/4.0/LEGALCODE",
        "https://creativecommons.org/%6Cicenses/by/4.0",
    ])
    func malformedCreativeCommonsPathSuffixesFailClosed(url: String) {
        let license = makeLicense(licenseURL: URL(string: url)!)

        #expect(license.validationIssues.contains(.invalidLicenseURL))
        #expect(!license.isApproved)
    }

    @Test(arguments: [
        (identifier: "CC-BY-NC", version: "4.0"),
        (identifier: "CC-BY-NC-SA", version: "4.0"),
        (identifier: "CC-BY-ND", version: "4.0"),
        (identifier: "CC-BY-NC-ND", version: "4.0"),
        (identifier: "UNKNOWN", version: "1.0"),
    ])
    func restrictedOrUnknownLicensesFailClosed(identifier: String, version: String) {
        let license = makeLicense(
            licenseIdentifier: identifier,
            licenseVersion: version
        )

        #expect(license.validationIssues.contains(.unsupportedLicense))
        #expect(!license.isApproved)
    }

    @Test
    func everyRequiredCreditAndProofFieldIsValidated() {
        let incompleteEntries = [
            makeLicense(assetName: ""),
            makeLicense(creator: "  "),
            makeLicense(sourceURL: URL(string: "http://example.com/source")!),
            makeLicense(licenseIdentifier: ""),
            makeLicense(licenseVersion: ""),
            makeLicense(licenseURL: URL(string: "http://example.com/license")!),
            makeLicense(modificationNote: ""),
            makeLicense(proofURL: URL(string: "http://example.com/proof")!),
        ]

        #expect(incompleteEntries.allSatisfy { !$0.isApproved })
    }

    @Test
    func oneInvalidOrDuplicateEntryRejectsTheWholeManifest() throws {
        let invalidManifest = SpeciesMediaManifest(entries: [
            makeLicense(species: .bass),
            makeLicense(species: .bluegill, licenseIdentifier: "CC-BY-NC"),
        ])
        let duplicateManifest = SpeciesMediaManifest(entries: [
            makeLicense(species: .bass),
            makeLicense(species: .bass, assetName: "bassSecondPhoto"),
        ])

        let invalidData = try JSONEncoder().encode(invalidManifest)
        let duplicateData = try JSONEncoder().encode(duplicateManifest)

        #expect(SpeciesMediaManifest.approvedEntries(from: invalidData).isEmpty)
        #expect(SpeciesMediaManifest.approvedEntries(from: duplicateData).isEmpty)
    }

    @Test
    func sourceAssetCatalogAndApprovedManifestStayInSync() throws {
        let mediaAssets = try recursivelyEnumeratedMediaAssets(in: speciesAssetDirectory)
        let mediaAssetNames = Set(mediaAssets.map(\.name))
        let entries = try sourceManifestEntries()
        let manifestExists = FileManager.default.fileExists(atPath: sourceManifestURL.path)

        #expect(Set(entries.values.map(\.assetName)) == mediaAssetNames)
        #expect(entries.count == mediaAssets.count)
        #expect(manifestExists == !mediaAssets.isEmpty)
    }

    @Test
    func recursiveAssetAuditFindsEveryNestedAssetPackageAndLoosePayload() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let packages = ["photo.imageset", "vector.symbolset", "archive.dataset"]
        for package in packages {
            let directory = root
                .appendingPathComponent("Freshwater/Nested", isDirectory: true)
                .appendingPathComponent(package, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try Data("{}".utf8).write(to: directory.appendingPathComponent("Contents.json"))
        }
        let loosePayload = root.appendingPathComponent("Saltwater/loose-photo.jpg")
        try FileManager.default.createDirectory(
            at: loosePayload.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0xFF, 0xD8, 0xFF]).write(to: loosePayload)

        let assets = try recursivelyEnumeratedMediaAssets(in: root)

        #expect(Set(assets.map(\.name)) == ["photo", "vector", "archive", "loose-photo"])
        #expect(Set(assets.map(\.kind)) == ["imageset", "symbolset", "dataset", "jpg"])
    }

    @Test
    func fallbackAccessibilityNamesTheSpeciesAndOwnership() {
        #expect(
            Species.bass.mediaAccessibilityLabel
                == "BiteCast illustration of Bass, Micropterus salmoides"
        )
        #expect(Species.all.mediaAccessibilityLabel == "BiteCast fish illustration")
    }

    @Test(arguments: [
        SpeciesPhotoView.Size.card,
        SpeciesPhotoView.Size.hero,
        SpeciesPhotoView.Size.square,
    ])
    func fallbackPresentationKeepsIdentityVisibleAtLargeDynamicType(
        size: SpeciesPhotoView.Size
    ) {
        let standard = SpeciesPhotoPresentation(
            size: size,
            isAccessibilitySize: false
        )
        let accessibility = SpeciesPhotoPresentation(
            size: size,
            isAccessibilitySize: true
        )

        #expect(standard.showsDisplayName)
        #expect(standard.showsScientificName)
        #expect(accessibility.showsDisplayName)
        #expect(accessibility.showsScientificName)
        #expect(accessibility.identityLineLimit == nil)
        #expect(accessibility.usesAccessibilityLayout)
        #expect(accessibility.ownershipStyle == .sealOnly)
        if size == .square {
            #expect(accessibility.identityStyle == .compact)
            #expect(accessibility.maximumIdentityDynamicTypeSize == .xxLarge)
        } else if size == .card {
            #expect(accessibility.maximumIdentityDynamicTypeSize == .xxxLarge)
        } else {
            #expect(accessibility.maximumIdentityDynamicTypeSize == .accessibility1)
        }
    }

    private var speciesAssetDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Support/Assets.xcassets/Species", isDirectory: true)
    }

    private var sourceManifestURL: URL {
        speciesAssetDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SpeciesMediaLicenses.json")
    }

    private func sourceManifestEntries() throws -> [Species: SpeciesMediaLicense] {
        guard FileManager.default.fileExists(atPath: sourceManifestURL.path) else { return [:] }
        let data = try Data(contentsOf: sourceManifestURL)
        return SpeciesMediaManifest.approvedEntries(from: data)
    }

    private func recursivelyEnumeratedMediaAssets(in root: URL) throws -> [MediaAsset] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var assets: [MediaAsset] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isDirectory == true {
                let assetKind = url.pathExtension.lowercased()
                guard !assetKind.isEmpty else { continue }
                assets.append(MediaAsset(
                    name: url.deletingPathExtension().lastPathComponent,
                    kind: assetKind
                ))
                enumerator.skipDescendants()
            } else if url.lastPathComponent != "Contents.json" {
                assets.append(MediaAsset(
                    name: url.deletingPathExtension().lastPathComponent,
                    kind: url.pathExtension.lowercased()
                ))
            }
        }
        return assets
    }

    private func makeLicense(
        species: Species = .bass,
        assetName: String = "bassPhoto",
        creator: String = "Jane Angler",
        sourceURL: URL = URL(string: "https://example.com/source")!,
        licenseIdentifier: String = "CC-BY",
        licenseVersion: String = "4.0",
        licenseURL: URL = URL(string: "https://creativecommons.org/licenses/by/4.0/")!,
        modificationNote: String = "Cropped for the species guide.",
        proofURL: URL = URL(string: "https://example.com/proof")!
    ) -> SpeciesMediaLicense {
        SpeciesMediaLicense(
            species: species,
            assetName: assetName,
            creator: creator,
            sourceURL: sourceURL,
            licenseIdentifier: licenseIdentifier,
            licenseVersion: licenseVersion,
            licenseURL: licenseURL,
            modificationNote: modificationNote,
            proofURL: proofURL
        )
    }


    private struct MediaAsset: Equatable {
        let name: String
        let kind: String
    }
}
