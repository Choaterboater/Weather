import FoundationModels
import UIKit

/// Turns a photo of a fishing spot into structured "where to cast" guidance,
/// grounded in Vision-detected scene features plus the day's conditions.
@MainActor
@Observable
final class WaterScout {
    enum Status: Equatable {
        case idle
        case unavailable(String)
        case working
        case ready
        case failed(String)
    }

    var status: Status = .idle
    var report: WaterScoutReport?

    func analyze(image: UIImage, species: Species, conditions: FishingConditions?) async {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable:
            status = .unavailable("On-device AI isn't available, so photo scouting is off. Turn on Apple Intelligence in Settings.")
            return
        @unknown default:
            status = .unavailable("On-device AI isn't available right now.")
            return
        }

        status = .working
        report = nil

        let imageData = image.pngData() ?? image.jpegData(compressionQuality: 0.8) ?? Data()
        let labels = await ImageSceneAnalyzer.labels(forImageData: imageData)
        let prompt = Self.prompt(labels: labels, species: species, conditions: conditions)

        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            report = try await session.respond(to: prompt, generating: WaterScoutReport.self).content
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func reset() {
        status = .idle
        report = nil
    }

    private static let instructions = """
    You are an expert freshwater fishing guide reading a spot from a photo. \
    You are given scene features detected in the image and the day's conditions. \
    Recommend where to cast and how, in practical terms. Be honest when the water \
    looks marginal. Don't claim to see details that weren't provided.
    """

    private static func prompt(labels: [String], species: Species, conditions: FishingConditions?) -> String {
        var lines: [String] = []
        if labels.isEmpty {
            lines.append("The photo shows a body of water; no distinct features were detected.")
        } else {
            lines.append("Detected in the photo: \(labels.joined(separator: ", ")).")
        }
        lines.append("Target species: \(species.promptName).")

        if let conditions {
            lines.append("Pressure is \(conditions.pressure.tendency.label.lowercased()).")
            lines.append("Moon: \(conditions.moonPhase.displayName) (\(conditions.moonPhase.biteRating.lowercased()) solunar).")
            if let active = conditions.activeWindow() {
                lines.append("A \(active.period.rawValue.lowercased()) bite window is active now.")
            } else if let next = conditions.nextWindow() {
                lines.append("Next bite window: \(next.period.rawValue.lowercased()) at \(next.peak.formatted(date: .omitted, time: .shortened)).")
            }
        }

        lines.append("Based on this, rate the water and tell me the single best place to cast and how to fish it.")
        return lines.joined(separator: "\n")
    }
}
