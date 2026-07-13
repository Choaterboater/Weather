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
    typealias AnswerWorker = @MainActor (String) async throws -> String

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
    private var generateID = 0
    private let answerWorker: AnswerWorker?

    init(answerWorker: AnswerWorker? = nil) {
        self.answerWorker = answerWorker
    }

    /// Whether the device can run the on-device model right now.
    var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(let reason): Self.message(for: reason)
        @unknown default: "On-device AI isn't available on this device."
        }
    }

    func reset() {
        generateID += 1
        status = .idle
        report = nil
        recommendation = nil
        answers = []
        session = nil
        isAnswering = false
    }

    func generate(
        conditions: FishingConditions,
        species: Species,
        tideEvents: [TideEvent] = []
    ) async {
        if let message = availabilityMessage {
            status = .unavailable(message)
            return
        }

        generateID += 1
        let id = generateID
        status = .working
        report = nil
        recommendation = nil

        let context = Self.contextSummary(
            conditions: conditions,
            species: species,
            tideEvents: tideEvents
        )
        let session = LanguageModelSession(instructions: Self.instructions)
        self.session = session

        do {
            let reportPrompt = """
            Write a 1–2 sentence, plain-language fishing report for these conditions. \
            Mention pressure trend, wind, and the best bite window if relevant.

            \(context)
            """
            let reportText = try await session.respond(to: reportPrompt).content
            guard id == generateID else { return }

            let baitPrompt = """
            Recommend the single best bait for \(species.promptName) given these conditions. \
            Be specific and practical.

            \(context)
            """
            let recommendation = try await session.respond(
                to: baitPrompt,
                generating: BaitRecommendation.self
            ).content
            guard id == generateID else { return }

            report = reportText
            self.recommendation = recommendation
            status = .ready
        } catch {
            guard id == generateID else { return }
            status = .failed(error.localizedDescription)
        }
    }

    /// Free-text follow-up that reuses the current session for context.
    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAnswering else { return }
        if answerWorker == nil, availabilityMessage != nil { return }

        let activeSession: LanguageModelSession?
        if answerWorker == nil {
            let session = self.session ?? LanguageModelSession(instructions: Self.instructions)
            self.session = session
            activeSession = session
        } else {
            activeSession = nil
        }
        let generation = generateID

        isAnswering = true
        defer {
            if Self.isCurrentGeneration(generation, current: generateID) {
                isAnswering = false
            }
        }
        do {
            let answer: String
            if let answerWorker {
                answer = try await answerWorker(trimmed)
            } else if let activeSession {
                answer = try await activeSession.respond(to: trimmed).content
            } else {
                return
            }
            guard Self.isCurrentGeneration(generation, current: generateID) else { return }
            answers.append(QAPair(question: trimmed, answer: answer))
        } catch {
            guard Self.isCurrentGeneration(generation, current: generateID) else { return }
            answers.append(QAPair(question: trimmed, answer: "Couldn't answer: \(error.localizedDescription)"))
        }
    }

    nonisolated static func isCurrentGeneration(_ requested: Int, current: Int) -> Bool {
        requested == current
    }

    // MARK: - Prompting

    private static let instructions = """
    You are an expert fishing guide. Give concise, practical advice grounded in \
    the weather and solunar conditions you're given. Match your bait suggestions \
    to the species's water type (freshwater vs saltwater). Prefer common, widely \
    available baits. Never invent data you weren't given.
    """

    private static func contextSummary(
        conditions: FishingConditions,
        species: Species,
        tideEvents: [TideEvent]
    ) -> String {
        var lines: [String] = []
        lines.append("Species focus: \(species.promptName)")

        let pressure = conditions.pressure
        if let measurement = pressure.pressure {
            let hpa = measurement.converted(to: .hectopascals).value
            lines.append("Pressure: \(Int(hpa.rounded())) hPa, \(pressure.tendency.label.lowercased())")
        } else {
            lines.append("Pressure: unavailable")
        }

        let windSpeed = WeatherUnits.milesPerHour(
            metersPerSecond: conditions.wind.speedMetersPerSecond
        )
        let windDirection = WeatherUnits.compassAbbreviation(
            degrees: conditions.wind.directionDegrees
        )
        lines.append("Wind: \(windDirection) \(Int(windSpeed.rounded())) mph")
        lines.append("UV index: \(conditions.uvIndex.map(String.init) ?? "unavailable")")
        lines.append("Moon: \(conditions.moonPhase.displayName) (\(conditions.moonPhase.biteRating.lowercased()) solunar)")

        if let active = conditions.activeWindow() {
            lines.append("Bite window: \(active.period.rawValue.lowercased()) active now until \(active.end.formatted(date: .omitted, time: .shortened))")
        } else if let next = conditions.nextWindow() {
            lines.append("Next bite window: \(next.period.rawValue.lowercased()) at \(next.peak.formatted(date: .omitted, time: .shortened))")
        }

        if !tideEvents.isEmpty {
            let now = Date.now
            let nearest = tideEvents.min(by: {
                abs($0.time.timeIntervalSince(now)) < abs($1.time.timeIntervalSince(now))
            })
            if let nearest {
                let minutes = Int(nearest.time.timeIntervalSince(now) / 60)
                let when = minutes >= 0
                    ? "in \(abs(minutes)) min"
                    : "\(abs(minutes)) min ago"
                lines.append("Tide: nearest \(nearest.kind.label.lowercased()) \(when)")
            }
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
