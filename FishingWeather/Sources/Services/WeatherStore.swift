import CoreLocation
import Foundation
import Observation

/// Loads and owns one provider-neutral snapshot for the active location.
@MainActor
@Observable
final class WeatherStore {
    typealias Worker = @Sendable (CLLocation, Date) async throws -> WeatherSnapshot
    typealias CacheWriter = @Sendable (WeatherSnapshot) async -> Void
    typealias Clock = @MainActor @Sendable () -> Date

    private(set) var snapshot: WeatherSnapshot?
    var isLoading = false
    private(set) var lastProviderError: WeatherProviderError?
    private(set) var loadedKey: String?

    /// Compatibility projection for existing views while new composition uses
    /// the typed provider error to choose an appropriate recovery state.
    var errorMessage: String? {
        lastProviderError?.localizedDescription
    }

    var provenance: WeatherProvenance? {
        snapshot?.provenance
    }

    private let worker: Worker
    private let cacheWriter: CacheWriter?
    private let now: Clock
    private var loadID = 0
    private let cacheTTL: TimeInterval = 15 * 60

    init(
        worker: @escaping Worker,
        cacheWriter: CacheWriter? = nil,
        now: @escaping Clock = { .now }
    ) {
        self.worker = worker
        self.cacheWriter = cacheWriter
        self.now = now
    }

    convenience init(
        provider: any WeatherProvider,
        cache: WeatherSnapshots? = nil,
        now: @escaping Clock = { .now }
    ) {
        let worker: Worker = { location, _ in
            try await provider.forecast(for: location)
        }
        if let cache {
            let writer: CacheWriter = { snapshot in
                try? await cache.save(snapshot)
            }
            self.init(worker: worker, cacheWriter: writer, now: now)
        } else {
            self.init(worker: worker, now: now)
        }
    }

    func hasData(for location: CLLocation) -> Bool {
        loadedKey == Self.cacheKey(for: location) && snapshot != nil
    }

    func load(for location: CLLocation, force: Bool = false) async {
        let key = Self.cacheKey(for: location)
        let requestDate = now()

        // A cache hit also supersedes an older in-flight location request.
        loadID += 1
        let id = loadID

        if !force,
           let snapshot,
           loadedKey == key {
            let age = requestDate.timeIntervalSince(snapshot.provenance.fetchedAt)
            if age >= 0, age < cacheTTL {
                isLoading = false
                lastProviderError = nil
                return
            }
        }

        if loadedKey != key {
            snapshot = nil
            loadedKey = nil
        }
        isLoading = true
        lastProviderError = nil

        do {
            let result = try await worker(location, requestDate)

            // No result from a superseded or canceled request may become
            // observable, including its loading/error state.
            guard id == loadID else { return }
            if Task.isCancelled {
                isLoading = false
                return
            }

            snapshot = result
            loadedKey = key
            isLoading = false
            lastProviderError = nil

            if result.provenance.source != .cache,
               let cacheWriter {
                await cacheWriter(result)
            }
        } catch {
            guard id == loadID else { return }
            if Task.isCancelled || Self.isCancellation(error) {
                isLoading = false
                return
            }

            isLoading = false
            lastProviderError = Self.providerError(for: error)
        }
    }

    static func cacheKey(for location: CLLocation) -> String {
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        return "\(lat),\(lon)"
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }

    private static func providerError(for error: any Error) -> WeatherProviderError {
        if let providerError = error as? WeatherProviderError {
            return providerError
        }
        return .network(String(describing: error))
    }
}
