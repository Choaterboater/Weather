import UIKit

/// Identifies a fish species from a photo via a Replicate vision model, mapping
/// the result onto the app's tracked species when possible.
@MainActor
@Observable
final class FishRecognizer {
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
        status = .working
        result = nil

        let scaled = Self.downscaled(image)
        let data = scaled.jpegData(compressionQuality: 0.8) ?? Data()

        // 1) On-device Core ML model, if one is bundled — free, offline, private.
        if let classifier = CoreMLFishClassifier(),
           let hit = await classifier.classify(imageData: data) {
            result = Self.make(label: hit.label, confidence: hit.confidence)
            status = .ready
            return
        }

        // 2) Cloud vision model via Replicate, if a token is set.
        guard let client = ReplicateVisionClient() else {
            status = .unavailable("For fish ID, bundle a Core ML model (FishClassifier) for on-device use, or add a Replicate API token.")
            return
        }

        do {
            let text = try await client.identify(imageData: data, prompt: Self.prompt)
            result = Self.parse(text)
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func reset() {
        status = .idle
        result = nil
    }

    private static let prompt = """
    Identify the freshwater fish species in this photo. Reply with the common \
    name only, for example "Largemouth Bass" or "Black Crappie". If it is not a \
    fish or you are unsure, say "Unknown".
    """

    /// Builds a result from a Core ML classification label + confidence.
    static func make(label: String, confidence: Float) -> FishIdentification {
        let lower = label.lowercased()
        let matched = Species.allCases.first { $0 != .all && lower.contains($0.rawValue) }
        let percent = Int((confidence * 100).rounded())
        return FishIdentification(
            commonName: label,
            matchedSpecies: matched,
            note: "On-device · \(percent)% confidence"
        )
    }

    static func parse(_ text: String) -> FishIdentification {
        let name = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let lower = name.lowercased()
        let matched = Species.allCases.first { $0 != .all && lower.contains($0.rawValue) }
        return FishIdentification(
            commonName: name.isEmpty ? "Unknown" : name,
            matchedSpecies: matched,
            note: matched == nil ? "Not one of the tracked species." : ""
        )
    }

    private static func downscaled(_ image: UIImage, maxDimension: CGFloat = 768) -> UIImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1 else { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
