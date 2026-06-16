import CoreML
import ImageIO
import Vision

/// On-device fish-species classifier backed by a bundled Core ML model.
///
/// Drop a species classifier compiled as `FishClassifier.mlmodelc` into the app
/// bundle (e.g. trained with Create ML on a freshwater-species dataset). When the
/// model isn't present, `init?` fails and the recognizer falls back to the cloud.
/// This path is free, offline, and private — no Replicate needed.
struct CoreMLFishClassifier {
    private let modelURL: URL

    init?(resourceName: String = "FishClassifier") {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mlmodelc") else {
            return nil
        }
        modelURL = url
    }

    func classify(imageData: Data) async -> (label: String, confidence: Float)? {
        let url = modelURL
        return await withCheckedContinuation { (continuation: CheckedContinuation<(String, Float)?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let mlModel = try? MLModel(contentsOf: url),
                      let visionModel = try? VNCoreMLModel(for: mlModel),
                      let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    continuation.resume(returning: nil)
                    return
                }

                let request = VNCoreMLRequest(model: visionModel)
                request.imageCropAndScaleOption = .centerCrop
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
                try? handler.perform([request])

                if let top = (request.results as? [VNClassificationObservation])?.first {
                    continuation.resume(returning: (top.identifier, top.confidence))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
