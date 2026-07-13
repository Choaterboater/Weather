import Foundation
import Observation
import UIKit

/// Observable interface to the private, on-device catch repository.
///
/// Entries change only after the protected transaction's journal is removed.
/// A failed add/delete therefore leaves both this observable collection and
/// the last committed on-disk log unchanged.
@MainActor
@Observable
final class CatchLog {
    struct ThumbnailLoad: @unchecked Sendable {
        let image: UIImage?
        let generatedData: Data?
    }

    typealias ThumbnailLoader = @Sendable (URL, URL, CGFloat) async -> ThumbnailLoad

    private(set) var entries: [CatchEntry] = []
    private(set) var lastErrorMessage: String?

    private let repository: CatchRepository
    @ObservationIgnored private let thumbnailLoader: ThumbnailLoader
    private let thumbnailCache = NSCache<NSString, UIImage>()
    @ObservationIgnored private var photoGenerations: [UUID: UInt64] = [:]

    /// Photos are only ever shown at list/detail size; storing the full 12MP
    /// original costs ~2-4 MB per catch and a ~47 MB decode per row.
    private static let storedPhotoMaxDimension: CGFloat = 1600
    private static let thumbnailMaxDimension: CGFloat = 240

    init(
        directory: URL? = nil,
        thumbnailLoader: ThumbnailLoader? = nil,
        protectionRecorder: @escaping CatchRepository.ProtectionRecorder = { _, _ in },
        failureInjector: @escaping CatchRepository.FailureInjector = { _ in }
    ) {
        let base = directory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        repository = CatchRepository(
            baseDirectory: base,
            protectionRecorder: protectionRecorder,
            failureInjector: failureInjector
        )
        self.thumbnailLoader = thumbnailLoader ?? Self.defaultThumbnailLoader
        do {
            entries = try repository.load()
        } catch {
            entries = repository.bestEffortEntries()
            lastErrorMessage = Self.loadErrorMessage(error)
        }
    }

    /// Internal paths are exposed for deterministic protection/recovery tests,
    /// not as a second persistence API for production views.
    var storagePaths: CatchRepository.Paths { repository.paths }

    func add(
        _ requestedEntry: CatchEntry,
        photo: UIImage?,
        now: Date = .now
    ) throws {
        do {
            let photoPayload = try Self.photoPayload(for: photo)
            let updated = try repository.add(
                requestedEntry,
                photoData: photoPayload?.photo,
                thumbnailData: photoPayload?.thumbnail,
                now: now,
                to: entries
            )
            entries = updated
            photoGenerations[requestedEntry.id, default: 0] &+= 1
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func remove(_ entry: CatchEntry) throws {
        do {
            let updated = try repository.remove(entry, from: entries)
            if let filename = entry.photoFilename {
                thumbnailCache.removeObject(forKey: filename as NSString)
            }
            entries = updated
            photoGenerations[entry.id, default: 0] &+= 1
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func clearError() {
        lastErrorMessage = nil
    }

    func photo(for entry: CatchEntry) -> UIImage? {
        guard let filename = entry.photoFilename,
              let url = try? repository.photoURL(for: filename) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Small row thumbnail, cached in memory and on disk. File I/O and decoding
    /// run off the main actor so list rows never hitch. A newly derived cache is
    /// handed back to the repository so it receives complete file protection.
    func thumbnail(for entry: CatchEntry) async -> UIImage? {
        guard let filename = entry.photoFilename else { return nil }
        if let cached = thumbnailCache.object(forKey: filename as NSString) {
            return cached
        }
        guard let thumbnailURL = try? repository.thumbnailURL(for: filename),
              let photoURL = try? repository.photoURL(for: filename) else { return nil }

        let maxDimension = Self.thumbnailMaxDimension
        let generation = photoGenerations[entry.id, default: 0]
        let loaded = await thumbnailLoader(thumbnailURL, photoURL, maxDimension)

        guard photoGenerations[entry.id, default: 0] == generation,
              entries.contains(where: {
                  $0.id == entry.id && $0.photoFilename == filename
              }) else {
            return nil
        }

        if let data = loaded.generatedData {
            // This is a reproducible cache, not a catch mutation. A failed cache
            // write leaves the protected source photo and metadata untouched.
            try? repository.storeThumbnail(data, filename: filename)
        }
        if let image = loaded.image {
            thumbnailCache.setObject(image, forKey: filename as NSString)
        }
        return loaded.image
    }

    private nonisolated static let defaultThumbnailLoader: ThumbnailLoader = {
        thumbnailURL,
        photoURL,
        maxDimension in
        await Task.detached(priority: .userInitiated) {
            if let existing = UIImage(contentsOfFile: thumbnailURL.path) {
                return ThumbnailLoad(image: existing, generatedData: nil)
            }
            guard let full = UIImage(contentsOfFile: photoURL.path) else {
                return ThumbnailLoad(image: nil, generatedData: nil)
            }
            let thumbnail = full.downscaled(maxDimension: maxDimension)
            return ThumbnailLoad(
                image: thumbnail,
                generatedData: thumbnail.jpegData(compressionQuality: 0.8)
            )
        }.value
    }

    // MARK: - Quick stats

    /// Most frequently caught species, if any catches are logged.
    var topSpecies: Species? {
        mostFrequent(entries.map(\.species))
    }

    /// Most productive bait by catch count, if recorded.
    var topBait: String? {
        let baits = entries.map(\.bait)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return mostFrequent(baits)
    }

    private func mostFrequent<T: Hashable>(_ values: [T]) -> T? {
        guard !values.isEmpty else { return nil }
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value < $1.value }?.key
    }

    private static func photoPayload(
        for photo: UIImage?
    ) throws -> (photo: Data, thumbnail: Data?)? {
        guard let photo else { return nil }
        let scaled = photo.downscaled(maxDimension: storedPhotoMaxDimension)
        guard let data = scaled.jpegData(compressionQuality: 0.8) else {
            throw CatchLogError.photoEncoding
        }
        let thumbnail = scaled.downscaled(maxDimension: thumbnailMaxDimension)
            .jpegData(compressionQuality: 0.8)
        return (data, thumbnail)
    }

    private static func loadErrorMessage(_ error: Error) -> String {
        "Catch history couldn't finish recovery. Your files were left in place. \(error.localizedDescription)"
    }
}

private enum CatchLogError: LocalizedError {
    case photoEncoding

    var errorDescription: String? {
        switch self {
        case .photoEncoding:
            "The catch photo couldn't be prepared. Nothing was saved."
        }
    }
}

/// Pure UI handoff used by both save and delete flows. Views dismiss/remove
/// presentation only when `committed` is true; failures retain the form/row and
/// carry a nonempty message into their alert state.
struct CatchOperationUIState: Equatable, Sendable {
    let committed: Bool
    let alertMessage: String?

    static func perform(_ operation: () throws -> Void) -> Self {
        do {
            try operation()
            return Self(committed: true, alertMessage: nil)
        } catch {
            return Self(
                committed: false,
                alertMessage: error.localizedDescription
            )
        }
    }
}
