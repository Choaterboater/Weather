import Foundation

/// Guards `URLSession` responses before decoding, so rate limits and outages
/// surface as readable errors instead of decode failures or silent empties.
struct HTTPStatusError: LocalizedError {
    let statusCode: Int

    var errorDescription: String? {
        switch statusCode {
        case 429: "The service is busy right now — try again in a minute."
        case 500...: "The service is having trouble (\(statusCode)). Try again later."
        default: "The request failed (\(statusCode))."
        }
    }

    /// Throws when the response carries a non-2xx HTTP status.
    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              !(200...299).contains(http.statusCode) else { return }
        throw HTTPStatusError(statusCode: http.statusCode)
    }
}
