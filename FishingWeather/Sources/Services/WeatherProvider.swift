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

extension WeatherProviderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authentication:
            "Weather authorization failed. Check the app's WeatherKit entitlement."
        case let .network(message):
            Self.nonEmpty(message) ?? "The weather service could not be reached."
        case let .rateLimited(retryAfter):
            if let retryAfter {
                "The weather service is busy. Try again in \(Int(retryAfter.rounded())) seconds."
            } else {
                "The weather service is busy. Try again shortly."
            }
        case .serviceUnavailable:
            "Weather is temporarily unavailable."
        case .unsupportedRegion:
            "Weather is not available for this location."
        case let .decoding(message):
            Self.nonEmpty(message) ?? "The weather response could not be read."
        case let .allProvidersFailed(failures):
            Self.representativeError(in: failures)?.errorDescription
                ?? "Weather is temporarily unavailable."
        }
    }

    private static func representativeError(
        in failures: [WeatherProviderFailure]
    ) -> WeatherProviderError? {
        let errors = failures.map(\.error)
        if let authentication = errors.first(where: { error in
            if case .authentication = error { return true }
            if case let .allProvidersFailed(nested) = error {
                return representativeError(in: nested) == .authentication
            }
            return false
        }) {
            if case let .allProvidersFailed(nested) = authentication {
                return representativeError(in: nested)
            }
            return authentication
        }

        for error in errors {
            if case let .allProvidersFailed(nested) = error,
               let representative = representativeError(in: nested) {
                return representative
            }
        }
        return errors.first
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
                    error: .network(String(describing: error))
                ))
            }
        }

        throw WeatherProviderError.allProvidersFailed(failures)
    }
}
