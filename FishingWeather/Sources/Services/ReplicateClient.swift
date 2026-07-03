import Foundation

/// Minimal Replicate client: create a prediction, wait/poll for it, return the
/// output image URL. No SDK — just `URLSession`. Returns `nil` from `init` when
/// there's no API token so callers can hide the feature cleanly.
struct ReplicateClient {
    enum ReplicateError: Error { case badResponse, failed(String), noOutput }

    private let runner: ReplicatePredictionRunner
    private let model: String

    /// Defaults to a fast, inexpensive text-to-image model.
    init?(model: String = "black-forest-labs/flux-schnell") {
        guard let token = AppSecrets.replicateToken else { return nil }
        runner = ReplicatePredictionRunner(token: token)
        self.model = model
    }

    func image(prompt: String) async throws -> URL {
        let output: [String]
        do {
            output = try await runner.run(
                model: model,
                input: [
                    "prompt": prompt,
                    "aspect_ratio": "1:1",
                    "output_format": "webp"
                ],
                outputType: [String].self,
                maxPollSeconds: 30
            )
        } catch let error as ReplicatePredictionRunner.RunnerError {
            throw ReplicateError(error)
        }
        guard let first = output.first, let outURL = URL(string: first) else {
            throw ReplicateError.noOutput
        }
        return outURL
    }
}

private extension ReplicateClient.ReplicateError {
    init(_ error: ReplicatePredictionRunner.RunnerError) {
        self = switch error {
        case .badResponse: .badResponse
        case .failed(let message): .failed(message)
        case .timedOut: .noOutput
        }
    }
}
