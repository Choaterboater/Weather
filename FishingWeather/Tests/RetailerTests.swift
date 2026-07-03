import Foundation
import Testing
@testable import BiteCast

/// Store search links are built from AI-generated bait names, which routinely
/// contain characters like "&" ("Salt & Pepper grub") that must be escaped.
@Suite("Retailer search URLs")
struct RetailerTests {
    private func queryValue(named name: String, in url: URL?) -> String? {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first { $0.name == name }?.value
    }

    @Test
    func ampersandInBaitNameStaysInsideTheSearchTerm() {
        let url = Retailer.amazon.searchURL(for: "salt & pepper grub fishing lure")
        #expect(queryValue(named: "k", in: url) == "salt & pepper grub fishing lure")
    }

    @Test
    func ebayQueryIsEscapedToo() {
        let url = Retailer.ebay.searchURL(for: "salt & pepper grub")
        #expect(queryValue(named: "_nkw", in: url) == "salt & pepper grub")
    }

    @Test
    func everyRetailerProducesAURL() {
        for retailer in Retailer.allCases {
            #expect(retailer.searchURL(for: "chartreuse spinnerbait") != nil)
        }
    }
}
