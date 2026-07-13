import UIKit

/// Identifies a fish species using only a bundled on-device Core ML model.
/// User photo bytes never leave the device.
@MainActor
@Observable
final class FishRecognizer {
    typealias Worker = @Sendable (Data) async throws -> FishIdentification

    private var task: Task<Void, Never>?
    private let worker: Worker?

    enum Status: Equatable {
        case idle
        case unavailable(String)
        case working
        case ready
        case failed(String)
    }

    var status: Status = .idle
    var result: FishIdentification?

    /// Production initializer. If no licensed model is bundled, recognition is
    /// honestly unavailable instead of uploading the user's photo elsewhere.
    init() {
        worker = Self.bundledWorker()
    }

    /// Test seam and explicit on-device worker injection. Passing nil disables
    /// recognition deterministically and proves there is no network fallback.
    init(worker: Worker?) {
        self.worker = worker
    }

    func identify(image: UIImage) async {
        task?.cancel()
        status = .working
        result = nil

        let currentSelf = self
        guard let worker else {
            status = .unavailable(Self.unavailableMessage)
            return
        }
        let activeTask = Task.detached(priority: .userInitiated) {
            let scaled = Self.downscaled(image)
            let data = scaled.jpegData(compressionQuality: 0.8) ?? Data()
            guard !Task.isCancelled else { return }

            do {
                let made = try await worker(data)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    currentSelf.result = made
                    currentSelf.status = .ready
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    currentSelf.status = .failed(error.localizedDescription)
                }
            }
        }
        task = activeTask
        await activeTask.value
    }

    func reset() {
        task?.cancel()
        task = nil
        status = .idle
        result = nil
    }

    nonisolated static let unavailableMessage =
        "Fish identification is unavailable because no licensed on-device model is installed. You can still choose the species yourself; this photo stays on your device."

    private nonisolated static func bundledWorker() -> Worker? {
        guard let classifier = CoreMLFishClassifier() else { return nil }
        return { data in
            guard let hit = await classifier.classify(imageData: data) else {
                throw FishRecognitionError.noResult
            }
            return Self.make(label: hit.label, confidence: hit.confidence)
        }
    }

    /// Builds a result from a Core ML classification label + confidence.
    nonisolated static func make(label: String, confidence: Float) -> FishIdentification {
        let matched = matchSpecies(in: label)
        let percent = Int((confidence * 100).rounded())
        return FishIdentification(
            commonName: label,
            matchedSpecies: matched,
            note: "On-device · \(percent)% confidence"
        )
    }

    /// Match on display name and common aliases, not just camelCase raw values.
    nonisolated static func matchSpecies(in text: String) -> Species? {
        let lower = text.lowercased()
        // Prefer longer display names first so "mangrove snapper" beats "snapper".
        let candidates = Species.allCases
            .filter { $0 != .all }
            .sorted { $0.displayName.count > $1.displayName.count }
        for species in candidates {
            if lower.contains(species.displayName.lowercased()) { return species }
            if lower.contains(species.rawValue.lowercased()) { return species }
        }
        // Aliases the model commonly returns.
        let aliases: [(String, Species)] = [
            ("largemouth", .bass),
            ("black bass", .bass),
            ("red drum", .redfish),
            ("channel cat", .catfish),
            ("spotted seatrout", .speckledTrout),
            ("speckled seatrout", .speckledTrout),
            ("seatrout", .speckledTrout),
            ("gray snapper", .mangroveSnapper),
            ("grey snapper", .mangroveSnapper),
        ]
        for (alias, species) in aliases where lower.contains(alias) {
            return species
        }
        return nil
    }

    private nonisolated static func downscaled(_ image: UIImage, maxDimension: CGFloat = 768) -> UIImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1 else { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

private enum FishRecognitionError: LocalizedError {
    case noResult

    var errorDescription: String? {
        "The on-device fish model couldn't identify this photo."
    }
}
