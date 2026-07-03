import Foundation

/// Sends an image + prompt to a Replicate vision model and returns its text
/// answer. Used for fish-species recognition. `init?` fails without a token.
///
/// On-device upgrade: when Foundation Models' native image input (WWDC 2026) is
/// confirmed for the shipped iOS 27 SDK, recognition can run on-device for free
/// by attaching the image to a `LanguageModelSession` prompt instead.
struct ReplicateVisionClient {
    enum VisionError: Error { case badResponse, failed(String), noOutput }

    private let runner: ReplicatePredictionRunner
    /// A vision-language model. Swap for a newer model id as Replicate's catalog evolves.
    private let model = "yorickvp/llava-13b"

    init?() {
        guard let token = AppSecrets.replicateToken else { return nil }
        runner = ReplicatePredictionRunner(token: token)
    }

    func identify(imageData: Data, prompt: String) async throws -> String {
        let dataURI = "data:image/jpeg;base64," + imageData.base64EncodedString()
        let output: OutputValue
        do {
            output = try await runner.run(
                model: model,
                input: ["image": dataURI, "prompt": prompt],
                outputType: OutputValue.self,
                maxPollSeconds: 60
            )
        } catch let error as ReplicatePredictionRunner.RunnerError {
            throw VisionError(error)
        }
        guard let text = output.text, !text.isEmpty else {
            throw VisionError.noOutput
        }
        return text
    }

    /// Replicate vision models return output as either a single string or an
    /// array of streamed string tokens.
    private enum OutputValue: Decodable, Sendable {
        case string(String)
        case strings([String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let single = try? container.decode(String.self) {
                self = .string(single)
            } else {
                self = .strings((try? container.decode([String].self)) ?? [])
            }
        }

        var text: String? {
            switch self {
            case .string(let value): value
            case .strings(let values): values.isEmpty ? nil : values.joined()
            }
        }
    }
}

private extension ReplicateVisionClient.VisionError {
    init(_ error: ReplicatePredictionRunner.RunnerError) {
        self = switch error {
        case .badResponse: .badResponse
        case .failed(let message): .failed(message)
        case .timedOut: .noOutput
        }
    }
}
