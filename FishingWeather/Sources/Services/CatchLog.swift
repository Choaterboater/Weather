import Foundation
import Observation
import UIKit

/// Stores logged catches as JSON in the Documents directory, with photos written
/// as separate files (kept out of the JSON and out of UserDefaults).
@MainActor
@Observable
final class CatchLog {
    private(set) var entries: [CatchEntry] = []

    private let fileURL: URL
    private let photosDirectory: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("catches.json")
        photosDirectory = documents.appendingPathComponent("CatchPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        load()
    }

    func add(_ entry: CatchEntry, photo: UIImage?) {
        var entry = entry
        if let photo, let data = photo.jpegData(compressionQuality: 0.8) {
            let filename = "\(entry.id.uuidString).jpg"
            try? data.write(to: photosDirectory.appendingPathComponent(filename))
            entry.photoFilename = filename
        }
        entries.insert(entry, at: 0)
        persist()
    }

    func remove(_ entry: CatchEntry) {
        if let filename = entry.photoFilename {
            try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(filename))
        }
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func photo(for entry: CatchEntry) -> UIImage? {
        guard let filename = entry.photoFilename else { return nil }
        return UIImage(contentsOfFile: photosDirectory.appendingPathComponent(filename).path)
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
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CatchEntry].self, from: data) else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL)
    }
}
