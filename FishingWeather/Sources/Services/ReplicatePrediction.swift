import Foundation

/// Shared engine for Replicate's prediction API: create with `Prefer: wait`,
/// then poll until the prediction reaches a *terminal* status. Streamed models
/// populate `output` incrementally, so a non-nil output alone does not mean
/// the model finished — polling on output truncated answers mid-stream.
struct ReplicatePredictionRunner {
    enum RunnerError: Error {
        case badResponse
        case failed(String)
        case timedOut
    }

    let token: String

    func run<Output: Decodable & Sendable>(
        model: String,
        input: [String: Any],
        outputType: Output.Type,
        maxPollSeconds: Int
    ) async throws -> Output {
        let endpoint = URL(string: "https://api.replicate.com/v1/models/\(model)/predictions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("wait", forHTTPHeaderField: "Prefer") // block until done when possible
        request.httpBody = try JSONSerialization.data(withJSONObject: ["input": input])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RunnerError.badResponse
        }

        var prediction = try JSONDecoder().decode(Prediction<Output>.self, from: data)

        var attempts = 0
        while !prediction.isTerminal, attempts < maxPollSeconds {
            // A dismissed view cancels its task; stop billing-relevant polling with it.
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(1))
            guard let pollURL = prediction.urls?.get.flatMap(URL.init(string:)) else { break }
            var poll = URLRequest(url: pollURL)
            poll.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (pollData, pollResponse) = try await URLSession.shared.data(for: poll)
            guard let pollHTTP = pollResponse as? HTTPURLResponse,
                  (200...299).contains(pollHTTP.statusCode) else {
                throw RunnerError.badResponse
            }
            prediction = try JSONDecoder().decode(Prediction<Output>.self, from: pollData)
            attempts += 1
        }

        if prediction.status == "failed" || prediction.status == "canceled" {
            throw RunnerError.failed(prediction.error ?? "prediction failed")
        }
        guard prediction.status == "succeeded", let output = prediction.output else {
            throw RunnerError.timedOut
        }
        return output
    }

    private struct Prediction<Output: Decodable & Sendable>: Decodable, Sendable {
        let status: String
        let output: Output?
        let error: String?
        let urls: URLs?

        struct URLs: Decodable, Sendable { let get: String? }

        var isTerminal: Bool {
            status == "succeeded" || status == "failed" || status == "canceled"
        }
    }
}
