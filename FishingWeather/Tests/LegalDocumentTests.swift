import Foundation
import Testing
@testable import BiteCast

@Suite("Offline legal documents")
struct LegalDocumentTests {
    @Test
    func legalCenterHasStableCompleteNavigationMetadata() {
        #expect(LegalDocument.allCases == [.privacy, .terms, .support, .thirdParty])
        #expect(Set(LegalDocument.allCases.map(\.resourceName)).count == 4)
        #expect(Set(LegalDocument.allCases.map(\.accessibilityIdentifier)).count == 4)
        #expect(LegalDocument.support.externalURL?.absoluteString
            == "https://github.com/Choaterboater/Weather")
    }

    @Test
    func legalBodyParserKeepsOfflineCopyReadableAndLinksActionable() {
        let body = LegalDocumentBody(text: """
        Heading

        Read this paragraph before continuing.

        https://example.org/legal
        """)

        #expect(body.blocks == [
            .text("Heading"),
            .text("Read this paragraph before continuing."),
            .link(URL(string: "https://example.org/legal")!),
        ])
    }

    @Test(arguments: [
        "Privacy",
        "Terms",
        "Support",
        "ThirdPartyNotices",
    ])
    func everyDocumentShipsAsReadableOfflineText(resourceName: String) throws {
        let url = legalDirectory.appendingPathComponent("\(resourceName).txt")
        let text = try String(contentsOf: url, encoding: .utf8)

        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(!text.contains("TODO"))
        #expect(!text.contains("<PLACEHOLDER>"))
    }

    @Test
    func titledDocumentsKeepTheirEffectiveDateInASeparateReadableBlock() throws {
        let privacy = LegalDocumentBody(text: try document(named: "Privacy"))
        let terms = LegalDocumentBody(text: try document(named: "Terms"))

        #expect(Array(privacy.blocks.prefix(2)) == [
            .text("BiteCast Privacy Notice"),
            .text("Effective July 13, 2026"),
        ])
        #expect(Array(terms.blocks.prefix(2)) == [
            .text("BiteCast Terms of Use"),
            .text("Effective July 13, 2026"),
        ])
    }

    @Test
    func everyDocumentLoadsFromTheBuiltAppBundle() throws {
        let store = LegalDocumentStore(bundle: .main)

        for document in LegalDocument.allCases {
            let body = try store.load(document)
            #expect(!body.blocks.isEmpty, "Missing bundled \(document.title)")
        }
    }

    @Test
    func debugAndReleasePermissionPromptsDiscloseEveryShippedUse() throws {
        for plistName in ["Info", "Info-Debug"] {
            let url = supportDirectory.appendingPathComponent("\(plistName).plist")
            let data = try Data(contentsOf: url)
            let object = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
            let plist = try #require(object as? [String: Any])
            let camera = try #require(plist["NSCameraUsageDescription"] as? String)
            let photos = try #require(plist["NSPhotoLibraryUsageDescription"] as? String)
            let location = try #require(
                plist["NSLocationWhenInUseUsageDescription"] as? String
            )

            #expect(camera.localizedCaseInsensitiveContains("photograph the water"))
            #expect(camera.localizedCaseInsensitiveContains("on-device"))
            #expect(photos.localizedCaseInsensitiveContains("catch"))
            #expect(photos.localizedCaseInsensitiveContains("log"))
            #expect(location.localizedCaseInsensitiveContains("save a catch location"))
        }
    }

    @Test
    func privacyDisclosureNamesEveryMaterialDataBoundary() throws {
        let privacy = try document(named: "Privacy")

        for requiredPhrase in [
            "Apple Weather",
            "National Weather Service",
            "OpenStreetMap",
            "iNaturalist",
            "Replicate",
            "precise location",
            "Catches, photos, and notes",
            "remove one catch",
        ] {
            #expect(privacy.localizedCaseInsensitiveContains(requiredPhrase))
        }
    }

    @Test
    func termsStateTheSafetyAndRegulationBoundaries() throws {
        let terms = try document(named: "Terms")

        for requiredPhrase in [
            "not an emergency",
            "not a navigation",
            "verify current fishing regulations",
            "artificial intelligence",
            "https://weatherkit.apple.com/legal-attribution.html",
        ] {
            #expect(terms.localizedCaseInsensitiveContains(requiredPhrase))
        }
    }

    @Test
    func thirdPartyNoticesContainTheShippedSourceAndLicenseLinks() throws {
        let notices = try document(named: "ThirdPartyNotices")

        for requiredLink in [
            "https://www.weather.gov/",
            "https://tidesandcurrents.noaa.gov/",
            "https://waterservices.usgs.gov/",
            "https://www.openstreetmap.org/copyright",
            "https://www.inaturalist.org/",
            "https://creativecommons.org/",
        ] {
            #expect(notices.contains(requiredLink))
        }
    }

    @Test
    func supportUsesARealProjectURLWithoutInventedContactDetails() throws {
        let support = try document(named: "Support")

        #expect(support.contains("https://github.com/Choaterboater/Weather"))
        #expect(!support.localizedCaseInsensitiveContains("example.com"))
        #expect(!support.localizedCaseInsensitiveContains("123 Main"))
    }

    private var legalDirectory: URL {
        supportDirectory.appendingPathComponent("Legal", isDirectory: true)
    }

    private var supportDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Support", isDirectory: true)
    }

    private func document(named name: String) throws -> String {
        try String(
            contentsOf: legalDirectory.appendingPathComponent("\(name).txt"),
            encoding: .utf8
        )
    }
}
