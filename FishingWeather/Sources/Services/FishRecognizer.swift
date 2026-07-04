import UIKit

/// Identifies a fish species from a photo via a Replicate vision model, mapping
/// the result onto the app's tracked species when possible.
@MainActor
@Observable
final class FishRecognizer {
    private var task: Task<Void, Never>?

    enum Status: Equatable {
        case idle
        case unavailable(String)
        case working
        case ready
        case failed(String)
    }

    var status: Status = .idle
    var result: FishIdentification?

    func identify(image: UIImage) async {
        task?.cancel()
        status = .working
        result = nil

        let prompt = Self.prompt
        let currentSelf = self
        task = Task.detached(priority: .userInitiated) {
            let scaled = Self.downscaled(image)
            let data = scaled.jpegData(compressionQuality: 0.8) ?? Data()

            // 1) On-device Core ML model
            if let classifier = CoreMLFishClassifier(),
               let hit = await classifier.classify(imageData: data) {
                guard !Task.isCancelled else { return }
                let made = Self.make(label: hit.label, confidence: hit.confidence)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    currentSelf.result = made
                    currentSelf.status = .ready
                }
                return
            }

            guard !Task.isCancelled else { return }

            // 2) Cloud vision model via Replicate, if a token is set
            guard let client = ReplicateVisionClient() else {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    currentSelf.status = .unavailable("For fish ID, bundle a Core ML model (FishClassifier) for on-device use, or add a Replicate API token.")
                }
                return
            }

            do {
                let text = try await client.identify(imageData: data, prompt: prompt)
                guard !Task.isCancelled else { return }
                let parsed = Self.parse(text)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    currentSelf.result = parsed
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
    }

    func reset() {
        task?.cancel()
        task = nil
        status = .idle
        result = nil
    }

    private static let prompt = """
    Identify the fish species in this photo (freshwater or saltwater). Reply with \
    the common name only, for example "Largemouth Bass", "Redfish", or "Speckled Trout". \
    If it is not a fish or you are unsure, say "Unknown".
    """

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

    nonisolated static func parse(_ text: String) -> FishIdentification {
        let name = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let matched = matchSpecies(in: name)
        return FishIdentification(
            commonName: name.isEmpty ? "Unknown" : name,
            matchedSpecies: matched,
            note: matched == nil ? "Not one of the tracked species." : ""
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
