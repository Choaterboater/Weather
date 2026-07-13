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
