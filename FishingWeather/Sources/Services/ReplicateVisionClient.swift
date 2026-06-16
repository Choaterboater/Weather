import Foundation

/// Sends an image + prompt to a Replicate vision model and returns its text
/// answer. Used for fish-species recognition. `init?` fails without a token.
///
/// On-device upgrade: when Foundation Models' native image input (WWDC 2026) is
/// confirmed for the shipped iOS 27 SDK, recognition can run on-device for free
/// by attaching the image to a `LanguageModelSession` prompt instead.
struct ReplicateVisionClient {
    enum VisionError: Error { case badResponse, failed(String), noOutput }

    private let token: String
    /// A vision-language model. Swap for a newer model id as Replicate's catalog evolves.
    private let model = "yorickvp/llava-13b"

    init?() {
        guard let token = AppSecrets.replicateToken else { return nil }
        self.token = token
    }

    func identify(imageData: Data, prompt: String) async throws -> String {
        let dataURI = "data:image/jpeg;base64," + imageData.base64EncodedString()
        let endpoint = URL(string: "https://api.replicate.com/v1/models/\(model)/predictions")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("wait", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "input": ["image": dataURI, "prompt": prompt]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw VisionError.badResponse
        }

        var prediction = try JSONDecoder().decode(Prediction.self, from: data)
        var attempts = 0
        while prediction.output?.text == nil,
              prediction.status != "failed",
              prediction.status != "canceled",
              attempts < 60 {
            try await Task.sleep(for: .seconds(1))
            guard let getURL = prediction.urls?.get.flatMap(URL.init(string:)) else { break }
            var poll = URLRequest(url: getURL)
            poll.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (pollData, _) = try await URLSession.shared.data(for: poll)
            prediction = try JSONDecoder().decode(Prediction.self, from: pollData)
            attempts += 1
        }

        if prediction.status == "failed" || prediction.status == "canceled" {
            throw VisionError.failed(prediction.error ?? "prediction failed")
        }
        guard let text = prediction.output?.text, !text.isEmpty else {
            throw VisionError.noOutput
        }
        return text
    }

    private struct Prediction: Decodable {
        let status: String
        let error: String?
        let urls: URLs?
        let output: OutputValue?

        struct URLs: Decodable { let get: String? }
    }

    /// Replicate vision models return output as either a single string or an
    /// array of streamed string tokens.
    private enum OutputValue: Decodable {
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
