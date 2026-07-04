import Foundation
import Testing
@testable import BiteCast

/// Revenue-bearing URL construction: the destination must survive the
/// affiliate-network round trip byte-for-byte.
@Suite("AffiliateLinkBuilder")
struct AffiliateLinkBuilderTests {
    private let destination = URL(string: "https://www.tacklewarehouse.com/search.html?keyword=chatterbait&color=green")!

    @Test
    func wrapsTheEncodedDestinationIntoTheTemplate() throws {
        let wrapped = AffiliateLinkBuilder.wrap(
            destination,
            template: "https://www.avantlink.com/click.php?tt=cl&mi=1234&pw=5678&url={url}"
        )
        let url = try #require(wrapped)
        #expect(url.absoluteString.hasPrefix("https://www.avantlink.com/click.php?tt=cl&mi=1234&pw=5678&url="))

        // Decoding the url parameter must give back the exact destination.
        let encoded = try #require(url.absoluteString.components(separatedBy: "url=").last)
        #expect(encoded.removingPercentEncoding == destination.absoluteString)
        // Nothing structural may leak through unencoded.
        #expect(!encoded.contains("&"))
        #expect(!encoded.contains("?"))
    }

    @Test
    func templateWithoutPlaceholderReturnsNil() {
        #expect(AffiliateLinkBuilder.wrap(destination, template: "https://example.com/click") == nil)
    }
}
