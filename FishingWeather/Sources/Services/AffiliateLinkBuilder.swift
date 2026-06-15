import Foundation

/// Wraps a destination URL in an affiliate-network deep link. Network-agnostic:
/// the template is whatever your network (AvantLink, Impact, CJ, …) provides,
/// with a `{url}` placeholder where the encoded destination goes.
///
/// AvantLink example:
///   https://www.avantlink.com/click.php?tt=cl&mi=1234&pw=5678&url={url}
/// Impact example (advertiser-specific vanity domain):
///   https://brand.sjv.io/c/AFFID/CAMPID?u={url}
enum AffiliateLinkBuilder {
    static func wrap(_ destination: URL, template: String) -> URL? {
        guard template.contains("{url}") else { return nil }
        let encoded = destination.absoluteString
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? destination.absoluteString
        let filled = template.replacingOccurrences(of: "{url}", with: encoded)
        return URL(string: filled)
    }
}
