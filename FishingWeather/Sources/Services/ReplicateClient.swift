import Foundation

/// Minimal Replicate client: create a prediction, wait/poll for it, return the
/// output image URL. No SDK — just `URLSession`. Returns `nil` from `init` when
/// there's no API token so callers can hide the feature cleanly.
struct ReplicateClient {
    enum ReplicateError: Error { case badResponse, failed(String), noOutput }

    private let token: String
    private let model: String

    /// Defaults to a fast, inexpensive text-to-image model.
    init?(model: String = "black-forest-labs/flux-schnell") {
        guard let token = AppSecrets.replicateToken else { return nil }
        self.token = token
        self.model = model
    }

    func image(prompt: String) async throws -> URL {
        let endpoint = URL(string: "https://api.replicate.com/v1/models/\(model)/predictions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("wait", forHTTPHeaderField: "Prefer") // block until done when possible
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "input": [
                "prompt": prompt,
                "aspect_ratio": "1:1",
                "output_format": "webp"
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ReplicateError.badResponse
        }

        var prediction = try JSONDecoder().decode(Prediction.self, from: data)

        // If `Prefer: wait` timed out before completion, poll the prediction.
        var attempts = 0
        while prediction.output == nil,
              prediction.status != "failed",
              prediction.status != "canceled",
              attempts < 30 {
            try await Task.sleep(for: .seconds(1))
            guard let getURL = prediction.urls?.get.flatMap(URL.init(string:)) else { break }
            var poll = URLRequest(url: getURL)
            poll.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (pollData, _) = try await URLSession.shared.data(for: poll)
            prediction = try JSONDecoder().decode(Prediction.self, from: pollData)
            attempts += 1
        }

        if prediction.status == "failed" || prediction.status == "canceled" {
            throw ReplicateError.failed(prediction.error ?? "prediction failed")
        }
        guard let first = prediction.output?.first, let outURL = URL(string: first) else {
            throw ReplicateError.noOutput
        }
        return outURL
    }

    private struct Prediction: Decodable {
        let status: String
        let output: [String]?
        let error: String?
        let urls: URLs?

        struct URLs: Decodable { let get: String? }
    }
}
