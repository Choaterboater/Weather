import Foundation
import UIKit

/// Fetches WeatherKit's provider-supplied combined marks with BiteCast's
/// contactable request identity. The validated bytes are embedded in the
/// temporary weather snapshot, so a still-valid cached Apple forecast retains
/// its required branding without another network request.
struct WeatherAttributionMarkLoader: Sendable {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let maximumMarkBytes = 2 * 1_024 * 1_024
    private let loader: Loader

    init(loader: @escaping Loader = Self.liveLoad) {
        self.loader = loader
    }

    func hydrate(
        _ attribution: WeatherProviderAttribution
    ) async throws -> WeatherProviderAttribution {
        guard attribution.providerKind == .appleWeather else {
            return attribution
        }
        guard let lightURL = attribution.combinedMarkLightURL,
              let darkURL = attribution.combinedMarkDarkURL else {
            throw Self.unavailable
        }

        do {
            async let light = markData(for: lightURL)
            async let dark = markData(for: darkURL)
            let (lightData, darkData) = try await (light, dark)
            let hydrated = WeatherProviderAttribution(
                providerKind: attribution.providerKind,
                serviceName: attribution.serviceName,
                legalPageURL: attribution.legalPageURL,
                combinedMarkLightURL: lightURL,
                combinedMarkDarkURL: darkURL,
                legalText: attribution.legalText,
                combinedMarkLightData: lightData,
                combinedMarkDarkData: darkData
            )
            guard Self.hasUsableAppleMarks(hydrated) else {
                throw Self.unavailable
            }
            return hydrated
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch let cancellation as URLError where cancellation.code == .cancelled {
            throw cancellation
        } catch {
            throw Self.unavailable
        }
    }

    static func hasUsableAppleMarks(
        _ attribution: WeatherProviderAttribution
    ) -> Bool {
        guard attribution.providerKind == .appleWeather,
              attribution.hasRequiredSecureMetadata,
              let light = attribution.combinedMarkLightData,
              let dark = attribution.combinedMarkDarkData
        else { return false }
        return UIImage(data: light) != nil && UIImage(data: dark) != nil
    }

    static func acceptsExpectedContentLength(_ length: Int64) -> Bool {
        length < 0 || length <= Int64(maximumMarkBytes)
    }

    private func markData(for url: URL) async throws -> Data {
        guard Self.isCanonicalHTTPS(url) else {
            throw Self.unavailable
        }
        var request = URLRequest(url: url)
        request.setValue(AppIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        let (data, response) = try await loader(request)
        guard let http = response as? HTTPURLResponse,
              let finalURL = http.url,
              Self.isCanonicalHTTPS(finalURL),
              (200..<300).contains(http.statusCode),
              http.mimeType?.lowercased().hasPrefix("image/") == true,
              !data.isEmpty,
              data.count <= Self.maximumMarkBytes,
              UIImage(data: data) != nil
        else { throw Self.unavailable }
        return data
    }

    fileprivate static func isCanonicalHTTPS(_ url: URL) -> Bool {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else { return false }
        return components.scheme?.lowercased() == "https"
            && components.host != nil
            && components.user == nil
            && components.password == nil
            && components.port == nil
            && components.fragment == nil
    }

    private static let unavailable = WeatherProviderError.decoding(
        "WeatherKit combined mark was unavailable"
    )

    private static func liveLoad(
        _ request: URLRequest
    ) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(
            for: request,
            delegate: WeatherAttributionRedirectDelegate()
        )
        guard acceptsExpectedContentLength(response.expectedContentLength) else {
            throw unavailable
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(Int(response.expectedContentLength))
        }
        for try await byte in bytes {
            guard data.count < maximumMarkBytes else {
                throw unavailable
            }
            data.append(byte)
        }
        return (data, response)
    }
}

private final class WeatherAttributionRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              WeatherAttributionMarkLoader.isCanonicalHTTPS(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
