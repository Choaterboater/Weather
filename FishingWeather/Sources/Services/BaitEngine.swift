import Foundation
import FoundationModels

/// Drives the on-device Foundation Models session to produce a plain-language
/// daily report and a structured bait recommendation, plus a free-text Q&A box.
///
/// WWDC 2026 note: this is written against `SystemLanguageModel`/`LanguageModelSession`.
/// The new `LanguageModel` provider protocol means the same session code can later
/// be pointed at Private Cloud Compute or a third-party model without changing the UI.
@MainActor
@Observable
final class BaitEngine {
    enum Status: Equatable {
        case idle
        case unavailable(String)
        case working
        case ready
        case failed(String)
    }

    struct QAPair: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    var status: Status = .idle
    var report: String?
    var recommendation: BaitRecommendation?
    var answers: [QAPair] = []
    var isAnswering = false

    private var session: LanguageModelSession?

    /// Whether the device can run the on-device model right now.
    var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(let reason): Self.message(for: reason)
        @unknown default: "On-device AI isn't available on this device."
        }
    }

    func reset() {
        status = .idle
        report = nil
        recommendation = nil
        answers = []
        session = nil
    }

    func generate(conditions: FishingConditions, species: Species) async {
        if let message = availabilityMessage {
            status = .unavailable(message)
            return
        }

        status = .working
        report = nil
        recommendation = nil

        let context = Self.contextSummary(conditions: conditions, species: species)
        let session = LanguageModelSession(instructions: Self.instructions)
        self.session = session

        do {
            let reportPrompt = """
            Write a 1–2 sentence, plain-language fishing report for these conditions. \
            Mention pressure trend, wind, and the best bite window if relevant.

            \(context)
            """
            report = try await session.respond(to: reportPrompt).content

            let baitPrompt = """
            Recommend the single best bait for \(species.promptName) given these conditions. \
            Be specific and practical.

            \(context)
            """
            recommendation = try await session.respond(
                to: baitPrompt,
                generating: BaitRecommendation.self
            ).content

            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Free-text follow-up that reuses the current session for context.
    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if availabilityMessage != nil { return }

        let session = self.session ?? LanguageModelSession(instructions: Self.instructions)
        self.session = session

        isAnswering = true
        defer { isAnswering = false }
        do {
            let answer = try await session.respond(to: trimmed).content
            answers.append(QAPair(question: trimmed, answer: answer))
        } catch {
            answers.append(QAPair(question: trimmed, answer: "Couldn't answer: \(error.localizedDescription)"))
        }
    }

    // MARK: - Prompting

    private static let instructions = """
    You are an expert freshwater fishing guide. Give concise, practical advice \
    grounded in the weather and solunar conditions you're given. Prefer common, \
    widely available baits. Never invent data you weren't given.
    """

    private static func contextSummary(conditions: FishingConditions, species: Species) -> String {
        var lines: [String] = []
        lines.append("Species focus: \(species.promptName)")

        let pressure = conditions.pressure
        let hpa = pressure.pressure.converted(to: .hectopascals).value
        lines.append("Pressure: \(Int(hpa)) hPa, \(pressure.tendency.label.lowercased())")

        let windSpeed = conditions.wind.speed.formatted(.measurement(width: .abbreviated, usage: .general))
        lines.append("Wind: \(conditions.wind.compassDirection.abbreviation) \(windSpeed)")
        lines.append("UV index: \(conditions.uvIndex.value)")
        lines.append("Moon: \(conditions.moonPhase.displayName) (\(conditions.moonPhase.biteRating.lowercased()) solunar)")

        if let active = conditions.activeWindow() {
            lines.append("Bite window: \(active.period.rawValue.lowercased()) active now until \(active.end.formatted(date: .omitted, time: .shortened))")
        } else if let next = conditions.nextWindow() {
            lines.append("Next bite window: \(next.period.rawValue.lowercased()) at \(next.peak.formatted(date: .omitted, time: .shortened))")
        }

        return lines.joined(separator: "\n")
    }

    private static func message(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "This device doesn't support on-device AI. The fishing facts above still work."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in Settings to get AI bait recommendations."
        case .modelNotReady:
            "The on-device model is still downloading. Try again in a bit."
        @unknown default:
            "On-device AI isn't available right now."
        }
    }
}
