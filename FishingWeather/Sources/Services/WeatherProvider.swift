import CoreLocation
import Foundation

protocol WeatherProvider: Sendable {
    func forecast(for location: CLLocation) async throws -> WeatherSnapshot
}

struct WeatherProviderFailure: Equatable, Sendable {
    let provider: String
    let error: WeatherProviderError
}

indirect enum WeatherProviderError: Error, Equatable, Sendable {
    case authentication
    case network(String?)
    case rateLimited(retryAfter: TimeInterval?)
    case serviceUnavailable
    case unsupportedRegion
    case decoding(String?)
    case allProvidersFailed([WeatherProviderFailure])
}

enum WeatherErrorPresentationKind: Equatable, Sendable {
    case authentication
    case network(message: String?)
    case rateLimited(retryAfter: TimeInterval?)
    case serviceUnavailable
    case unsupportedRegion
    case decoding(message: String?)
}

extension WeatherProviderError {
    /// Normalizes an untyped provider failure without guessing about
    /// connectivity from prose. Only Foundation's explicit
    /// `notConnectedToInternet` code becomes the canonical offline error.
    static func from(_ error: any Error) -> Self {
        if let providerError = error as? Self {
            return providerError
        }
        if let urlError = error as? URLError,
           urlError.code == .notConnectedToInternet {
            return .network(Self.offlineMessage)
        }
        return .serviceUnavailable
    }

    /// Positive connectivity classification. Generic `.network` values from
    /// older provider adapters remain service failures unless they carry the
    /// canonical marker created by `from(_:)`.
    var isOffline: Bool {
        switch self {
        case let .network(message):
            return message == Self.offlineMessage
        case let .allProvidersFailed(failures):
            return failures.contains { $0.error.isOffline }
        default:
            return false
        }
    }

    /// A provider-neutral presentation category. Aggregate failures recurse
    /// through nested chains, preferring authentication because it is the one
    /// failure a developer must fix rather than asking the user to retry.
    var presentationKind: WeatherErrorPresentationKind {
        switch self {
        case .authentication:
            return .authentication
        case let .network(message):
            return message == Self.offlineMessage
                ? .network(message: message)
                : .serviceUnavailable
        case let .rateLimited(retryAfter):
            return .rateLimited(retryAfter: retryAfter)
        case .serviceUnavailable:
            return .serviceUnavailable
        case .unsupportedRegion:
            return .unsupportedRegion
        case let .decoding(message):
            return .decoding(message: message)
        case let .allProvidersFailed(failures):
            let kinds = failures.map(\.error.presentationKind)
            return kinds.first(where: \.isAuthentication)
                ?? kinds.first
                ?? .serviceUnavailable
        }
    }

    private static let offlineMessage = "offline"
}

extension WeatherProviderError: LocalizedError {
    var errorDescription: String? {
        presentationKind.errorDescription
    }
}

private extension WeatherErrorPresentationKind {
    var isAuthentication: Bool {
        if case .authentication = self { return true }
        return false
    }

    var errorDescription: String {
        switch self {
        case .authentication:
            "Weather authorization failed. Check the app's WeatherKit entitlement."
        case let .network(message: message):
            Self.nonEmpty(message) ?? "The weather service could not be reached."
        case let .rateLimited(retryAfter: retryAfter):
            if let retryAfter {
                "The weather service is busy. Try again in \(Int(retryAfter.rounded())) seconds."
            } else {
                "The weather service is busy. Try again shortly."
            }
        case .serviceUnavailable:
            "Weather is temporarily unavailable."
        case .unsupportedRegion:
            "Weather is not available for this location."
        case let .decoding(message: message):
            Self.nonEmpty(message) ?? "The weather response could not be read."
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return value
    }
}

struct WeatherProviderChain: WeatherProvider {
    let providers: [any WeatherProvider]

    func forecast(for location: CLLocation) async throws -> WeatherSnapshot {
        var failures: [WeatherProviderFailure] = []

        for (index, provider) in providers.enumerated() {
            do {
                let snapshot = try await provider.forecast(for: location)
                return snapshot.markingFallback(index > 0)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let cancellation as URLError where cancellation.code == .cancelled {
                throw cancellation
            } catch let error as WeatherProviderError {
                failures.append(WeatherProviderFailure(
                    provider: String(describing: type(of: provider)),
                    error: error
                ))
            } catch {
                failures.append(WeatherProviderFailure(
                    provider: String(describing: type(of: provider)),
                    error: WeatherProviderError.from(error)
                ))
            }
        }

        throw WeatherProviderError.allProvidersFailed(failures)
    }
}
