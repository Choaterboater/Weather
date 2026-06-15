import UIKit
import Vision

/// Extracts scene labels from a photo with the Vision framework. These ground the
/// language model's advice in what's actually in the picture (water, trees, dock,
/// shoreline, etc.).
///
/// When Foundation Models' native image input (WWDC 2026) is confirmed for the
/// shipped SDK, this pre-pass can be replaced by attaching the image directly to
/// the prompt for finer-grained, position-aware guidance.
enum ImageSceneAnalyzer {
    static func labels(for image: UIImage, limit: Int = 6) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        nonisolated(unsafe) let source = cgImage

        return await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: source, orientation: .up)
                try? handler.perform([request])

                let labels = (request.results ?? [])
                    .filter { $0.confidence > 0.15 }
                    .prefix(limit)
                    .map(\.identifier)
                continuation.resume(returning: Array(labels))
            }
        }
    }
}
