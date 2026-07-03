import Foundation
import Observation
import UIKit

/// Stores logged catches as JSON in the Documents directory, with photos written
/// as separate files (kept out of the JSON and out of UserDefaults).
///
/// Persistence safety: writes are atomic, an unreadable file is backed up (never
/// silently replaced — catch history is irreplaceable), and one malformed entry
/// doesn't discard the rest.
@MainActor
@Observable
final class CatchLog {
    private(set) var entries: [CatchEntry] = []

    private let directory: URL
    private let fileURL: URL
    private let photosDirectory: URL
    private let thumbnailCache = NSCache<NSString, UIImage>()

    /// Photos are only ever shown at list/detail size; storing the full 12MP
    /// original costs ~2-4 MB per catch and a ~47 MB decode per row.
    private static let storedPhotoMaxDimension: CGFloat = 1600
    private static let thumbnailMaxDimension: CGFloat = 240

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.directory = base
        fileURL = base.appendingPathComponent("catches.json")
        photosDirectory = base.appendingPathComponent("CatchPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        load()
    }

    func add(_ entry: CatchEntry, photo: UIImage?) {
        var entry = entry
        if let photo {
            let scaled = photo.downscaled(maxDimension: Self.storedPhotoMaxDimension)
            if let data = scaled.jpegData(compressionQuality: 0.8) {
                let filename = "\(entry.id.uuidString).jpg"
                do {
                    try data.write(to: photosDirectory.appendingPathComponent(filename), options: .atomic)
                    entry.photoFilename = filename
                    writeThumbnail(from: scaled, filename: filename)
                } catch {
                    // Keep the entry; just don't point it at a photo that isn't there.
                }
            }
        }
        entries.insert(entry, at: 0)
        persist()
    }

    func remove(_ entry: CatchEntry) {
        if let filename = entry.photoFilename {
            try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(filename))
            try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(Self.thumbnailName(for: filename)))
            thumbnailCache.removeObject(forKey: filename as NSString)
        }
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func photo(for entry: CatchEntry) -> UIImage? {
        guard let filename = entry.photoFilename else { return nil }
        return UIImage(contentsOfFile: photosDirectory.appendingPathComponent(filename).path)
    }

    /// Small row thumbnail, cached in memory and on disk. File I/O and decoding
    /// run off the main actor so list rows never hitch.
    func thumbnail(for entry: CatchEntry) async -> UIImage? {
        guard let filename = entry.photoFilename else { return nil }
        if let cached = thumbnailCache.object(forKey: filename as NSString) { return cached }

        let thumbURL = photosDirectory.appendingPathComponent(Self.thumbnailName(for: filename))
        let photoURL = photosDirectory.appendingPathComponent(filename)
        let maxDimension = Self.thumbnailMaxDimension
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            if let existing = UIImage(contentsOfFile: thumbURL.path) { return existing }
            // Entries logged before thumbnails existed: derive one now.
            guard let full = UIImage(contentsOfFile: photoURL.path) else { return nil }
            let thumb = full.downscaled(maxDimension: maxDimension)
            try? thumb.jpegData(compressionQuality: 0.8)?.write(to: thumbURL, options: .atomic)
            return thumb
        }.value

        if let image { thumbnailCache.setObject(image, forKey: filename as NSString) }
        return image
    }

    private func writeThumbnail(from image: UIImage, filename: String) {
        let thumb = image.downscaled(maxDimension: Self.thumbnailMaxDimension)
        let url = photosDirectory.appendingPathComponent(Self.thumbnailName(for: filename))
        try? thumb.jpegData(compressionQuality: 0.8)?.write(to: url, options: .atomic)
        thumbnailCache.setObject(thumb, forKey: filename as NSString)
    }

    nonisolated private static func thumbnailName(for filename: String) -> String {
        "thumb-" + filename
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

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([CatchEntry].self, from: data) {
            entries = decoded
            return
        }
        // The file exists but doesn't decode cleanly (schema change, corrupt
        // write, …). Preserve the original bytes before anything can overwrite
        // them, then salvage whatever entries still decode.
        backUpUnreadableFile(data)
        if let salvaged = try? JSONDecoder().decode([FailableEntry].self, from: data) {
            entries = salvaged.compactMap(\.value)
        }
    }

    private func backUpUnreadableFile(_ data: Data) {
        let name = "catches-recovered-\(UUID().uuidString).json"
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        // Atomic replace: a crash mid-write leaves the old file, never a torn one.
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Decodes to nil instead of failing the whole array. File scope so the
/// synthesized/handwritten decoding stays free of the log's actor isolation.
private struct FailableEntry: Decodable {
    let value: CatchEntry?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(CatchEntry.self)
    }
}
