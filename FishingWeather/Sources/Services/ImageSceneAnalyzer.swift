import ImageIO
import Vision

/// Extracts scene labels from photo data with the Vision framework. These ground
/// the language model's advice in what's actually in the picture (water, trees,
/// dock, shoreline, etc.).
///
/// Takes `Data` (which is `Sendable`) and builds the `CGImage` inside the work
/// closure, so no non-`Sendable` image type crosses a concurrency boundary.
///
/// When Foundation Models' native image input (WWDC 2026) is confirmed for the
/// shipped SDK, this pre-pass can be replaced by attaching the image directly to
/// the prompt for finer-grained, position-aware guidance.
enum ImageSceneAnalyzer {
    static func labels(forImageData data: Data, limit: Int = 6) async -> [String] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    continuation.resume(returning: [])
                    return
                }

                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
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
