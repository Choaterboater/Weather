import CoreLocation
import Foundation
import FoundationModels

/// Stable identity for one conditions-aware bait decision.
///
/// The selected provider hour, rather than wall-clock time, owns the time
/// bucket. That keeps chart selection and bait advice in the same context.
struct BaitContextKey: Hashable, Sendable {
    let species: Species
    let locationKey: String
    let weatherFetchedAt: Date
    let tideFingerprint: String
    let forecastHourBucket: Int64
    let inputFingerprint: String

    static func canGenerate(for species: Species) -> Bool {
        species != .all
    }

    static func make(
        species: Species,
        coordinate: CLLocationCoordinate2D,
        weatherFetchedAt: Date,
        tideFingerprint: String,
        forecastPoint: ForecastPoint,
        inputFingerprint: String
    ) -> BaitContextKey? {
        guard canGenerate(for: species),
              coordinate.latitude.isFinite,
              coordinate.longitude.isFinite,
              (-90...90).contains(coordinate.latitude),
              (-180...180).contains(coordinate.longitude),
              weatherFetchedAt.timeIntervalSinceReferenceDate.isFinite,
              forecastPoint.date.timeIntervalSince1970.isFinite
        else { return nil }

        let rawBucket = floor(
            forecastPoint.date.timeIntervalSince1970 / 3_600
        )
        guard let bucket = Int64(exactly: rawBucket) else { return nil }

        return BaitContextKey(
            species: species,
            locationKey: roundedLocationKey(for: coordinate),
            weatherFetchedAt: weatherFetchedAt,
            tideFingerprint: tideFingerprint,
            forecastHourBucket: bucket,
            inputFingerprint: inputFingerprint
        )
    }

    /// Fingerprints the exact sanitized facts supplied to the model. The
    /// surrounding prompt is static, so a changed value here represents a
    /// changed recommendation input even when the base forecast identity is
    /// unchanged.
    static func inputFingerprint(for promptSummary: String) -> String {
        stableFingerprint(promptSummary.utf8)
    }

    /// Fingerprints only committed tide values supplied by `TideService`.
    /// Swift's randomized `Hasher` is intentionally avoided so the same data
    /// produces the same value across launches.
    static func tideFingerprint(
        events: [TideEvent],
        samples: [TideSample]
    ) -> String {
        let eventParts = events
            .map {
                let height = $0.heightFeet.map(canonical) ?? "nil"
                return "event|\(canonical($0.time.timeIntervalSince1970))"
                    + "|\($0.kind.rawValue)"
                    + "|\(height)"
            }
            .sorted()
        let sampleParts = samples
            .map {
                "sample|\(canonical($0.time.timeIntervalSince1970))"
                    + "|\(canonical($0.heightFeet))"
            }
            .sorted()
        let bytes = (eventParts + sampleParts)
            .joined(separator: "\n")
            .utf8

        return stableFingerprint(bytes)
    }

    private static func roundedLocationKey(
        for coordinate: CLLocationCoordinate2D
    ) -> String {
        "\(coordinatePart(coordinate.latitude)),"
            + coordinatePart(coordinate.longitude)
    }

    private static func coordinatePart(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        let normalized = rounded == 0 ? 0 : rounded
        return String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            normalized
        )
    }

    private static func canonical(_ value: Double) -> String {
        String(
            format: "%.17g",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    private static func stableFingerprint<Bytes: Sequence>(
        _ bytes: Bytes
    ) -> String where Bytes.Element == UInt8 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

/// The exact provider-neutral hour described to the model.
///
/// `promptSummary` is captured from `forecastPoint` at initialization. It never
/// consults `Date.now` or a separate current-conditions object.
struct BestBaitContext: Equatable, Sendable {
    let key: BaitContextKey
    let species: Species
    let forecastPoint: ForecastPoint
    let promptSummary: String

    init?(
        species: Species,
        coordinate: CLLocationCoordinate2D,
        weatherFetchedAt: Date,
        tideFingerprint: String,
        forecastPoint: ForecastPoint
    ) {
        guard forecastPoint.date.timeIntervalSince1970.isFinite else {
            return nil
        }
        let promptSummary = Self.summary(
            species: species,
            point: forecastPoint
        )
        guard let key = BaitContextKey.make(
            species: species,
            coordinate: coordinate,
            weatherFetchedAt: weatherFetchedAt,
            tideFingerprint: tideFingerprint,
            forecastPoint: forecastPoint,
            inputFingerprint: BaitContextKey.inputFingerprint(
                for: promptSummary
            )
        ) else { return nil }

        self.key = key
        self.species = species
        self.forecastPoint = forecastPoint
        self.promptSummary = promptSummary
    }

    private static func summary(
        species: Species,
        point: ForecastPoint
    ) -> String {
        let weather = point.weather
        var lines = [
            "Species focus: \(species.promptName)",
            "Selected forecast hour: \(iso8601(point.date))",
        ]

        if let temperature = finite(weather.temperatureCelsius) {
            lines.append("Air temperature: \(number(temperature)) C")
        } else {
            lines.append("Air temperature: unavailable")
        }
        lines.append("Condition: \(weather.conditionText)")

        if let apparent = finite(weather.apparentTemperatureCelsius) {
            lines.append("Feels like: \(number(apparent)) C")
        }
        if let chance = fraction(weather.precipitationChance) {
            lines.append(
                "Precipitation chance: \(Int((chance * 100).rounded())) percent"
            )
        } else {
            lines.append("Precipitation chance: unavailable")
        }
        if let pressure = finite(weather.pressureHPa) {
            let tendency = point.pressureTendency?.label ?? "Trend unavailable"
            lines.append(
                "Pressure: \(number(pressure)) hPa, \(tendency)"
            )
        } else {
            lines.append("Pressure: unavailable")
        }

        if let direction = windDirection(weather.wind.directionDegrees),
           let speed = nonnegative(weather.wind.speedMetersPerSecond),
           let windMPH = finite(WeatherUnits.milesPerHour(
               metersPerSecond: speed
           )) {
            let roundedDirection = Int(direction.rounded()) % 360
            var windLine = "Wind: \(roundedDirection) degrees at "
                + "\(number(windMPH)) mph"
            if let gust = nonnegative(weather.wind.gustMetersPerSecond),
               let gustMPH = finite(WeatherUnits.milesPerHour(
                   metersPerSecond: gust
               )) {
                windLine += ", gusting \(number(gustMPH)) mph"
            }
            lines.append(windLine)
        } else {
            lines.append("Wind: unavailable")
        }

        if let tideHeight = finite(point.tideHeightFeet) {
            var tideLine = "Tide: \(number(tideHeight)) ft"
            if let tidePhase = point.tidePhase {
                tideLine += ", \(tidePhase)"
            }
            if let rate = finite(point.tideRateFeetPerHour) {
                tideLine += ", rate \(number(rate)) ft/hr"
            }
            lines.append(tideLine)
        } else {
            lines.append("Tide: unavailable")
        }

        if let nextTurn = point.nextTideTurn,
           isFinite(nextTurn.time) {
            lines.append(
                "Next tide turn: \(nextTurn.kind.label) at "
                    + iso8601(nextTurn.time)
            )
        }
        if let window = point.solunarWindow,
           isFinite(window.peak) {
            lines.append(
                "Solunar window: \(window.period.rawValue), \(window.cause), "
                    + "peak \(iso8601(window.peak))"
            )
        } else if point.solunarWindow != nil {
            lines.append("Solunar window: unavailable")
        } else {
            lines.append("Solunar window: none active for the selected hour")
        }
        if let moonPhase = point.moonPhase {
            lines.append("Moon: \(moonPhase.displayName)")
        }
        if let biteScore = point.biteScore,
           (0...100).contains(biteScore) {
            lines.append("Deterministic bite score: \(biteScore)/100")
        } else {
            lines.append("Deterministic bite score: unavailable")
        }

        return lines.joined(separator: "\n")
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func fraction(_ value: Double?) -> Double? {
        guard let value = finite(value), (0...1).contains(value) else {
            return nil
        }
        return value
    }

    private static func nonnegative(_ value: Double?) -> Double? {
        guard let value = finite(value), value >= 0 else { return nil }
        return value
    }

    private static func windDirection(_ value: Double) -> Double? {
        guard value.isFinite, (0...360).contains(value) else { return nil }
        return value
    }

    private static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }

    private static func number(_ value: Double) -> String {
        String(
            format: "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

struct BestBaitResult: Equatable {
    enum Source: Equatable {
        case onDeviceAppleIntelligence(generatedAt: Date)
        case generalSpeciesGuidance
    }

    static let generalGuidanceLabel =
        "General species guidance — not adjusted for today"

    let key: BaitContextKey
    let recommendation: BaitRecommendation
    let source: Source

    var sourceLabel: String {
        switch source {
        case .onDeviceAppleIntelligence:
            "On-device Apple Intelligence"
        case .generalSpeciesGuidance:
            Self.generalGuidanceLabel
        }
    }

    var generatedAt: Date? {
        guard case .onDeviceAppleIntelligence(let generatedAt) = source else {
            return nil
        }
        return generatedAt
    }

    /// Source-aware fields consumed by both bait surfaces. The profile
    /// fallback has no evidence for a color or exact depth, so its profile
    /// habitat remains visible without being mislabeled as either.
    var presentationColor: String? {
        guard case .onDeviceAppleIntelligence = source else { return nil }
        let trimmed = recommendation.color.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : recommendation.color
    }

    var presentationDetailLabel: String {
        switch source {
        case .onDeviceAppleIntelligence:
            "Depth"
        case .generalSpeciesGuidance:
            "Habitat"
        }
    }

    var presentationDetailValue: String {
        recommendation.depth
    }

    var presentationDetailSystemImage: String {
        switch source {
        case .onDeviceAppleIntelligence:
            "arrow.down.to.line"
        case .generalSpeciesGuidance:
            "water.waves"
        }
    }
}

/// Owns one structured bait result per explicit selected-hour context.
@MainActor
@Observable
final class BaitEngine {
    typealias RecommendationWorker = @MainActor (
        BestBaitContext
    ) async throws -> BaitRecommendation
    typealias AdviceWorker = @MainActor (
        BestBaitContext,
        BaitRecommendation
    ) async throws -> String
    typealias AnswerWorker = @MainActor (String) async throws -> String
    typealias ModelAvailabilityProvider = @MainActor () -> ModelAvailability
    typealias Clock = @MainActor () -> Date

    enum ModelAvailability: Equatable {
        case available
        case unavailable(String)
    }

    enum Status: Equatable {
        case idle
        case chooseSpecies
        case missingContext
        case working
        case ready
    }

    struct QAPair: Identifiable, Equatable {
        let id = UUID()
        let question: String
        let answer: String
    }

    var status: Status = .idle
    var result: BestBaitResult?
    var report: String?
    var adviceError: String?
    var isGeneratingAdvice = false
    var answers: [QAPair] = []
    var isAnswering = false

    /// Q&A is offered only for a current model-authored result. Injected answer
    /// workers can still exercise the lower-level identity behavior in tests.
    var canAnswer: Bool {
        guard case .onDeviceAppleIntelligence = result?.source else {
            return false
        }
        return !isGeneratingAdvice && (answerWorker != nil || session != nil)
    }

    private struct InFlight {
        let key: BaitContextKey
        let generation: Int
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private enum GenerationOutcome {
        case success(BaitRecommendation, generatedAt: Date)
        case failure(String)
    }

    private let modelAvailability: ModelAvailabilityProvider
    private let recommendationWorker: RecommendationWorker?
    private let adviceWorker: AdviceWorker?
    private let answerWorker: AnswerWorker?
    private let clock: Clock

    private var session: LanguageModelSession?
    private var activeContext: BestBaitContext?
    private var inFlight: InFlight?
    private var generation = 0

    init(
        modelAvailability: ModelAvailabilityProvider? = nil,
        recommendationWorker: RecommendationWorker? = nil,
        adviceWorker: AdviceWorker? = nil,
        answerWorker: AnswerWorker? = nil,
        clock: @escaping Clock = { .now }
    ) {
        self.modelAvailability = modelAvailability ?? {
            Self.systemModelAvailability
        }
        self.recommendationWorker = recommendationWorker
        self.adviceWorker = adviceWorker
        self.answerWorker = answerWorker
        self.clock = clock
    }

    func reset() {
        invalidate(for: nil)
        status = .idle
    }

    func generateBestBait(
        for species: Species,
        context: BestBaitContext?,
        force: Bool = false
    ) async {
        guard species != .all else {
            invalidate(for: nil)
            status = .chooseSpecies
            return
        }
        guard let context, context.species == species else {
            invalidate(for: nil)
            status = .missingContext
            return
        }

        switch modelAvailability() {
        case .unavailable(let message):
            let id = invalidate(for: context)
            publishFallback(
                for: context,
                generation: id,
                modelMessage: message
            )
            return
        case .available:
            break
        }

        if !force,
           let current = inFlight,
           current.key == context.key {
            await waitForCoalescedRequest(
                key: context.key,
                generation: current.generation
            )
            return
        }

        if !force,
           result?.key == context.key,
           case .onDeviceAppleIntelligence = result?.source {
            return
        }

        let id = invalidate(for: context)
        status = .working
        inFlight = InFlight(key: context.key, generation: id)

        let outcome = await generateStructuredRecommendation(for: context)
        commit(outcome, for: context, generation: id)
        finishInFlight(generation: id)
    }

    /// Generates the optional plain-language report only after the explicit
    /// More Advice action has presented its secondary surface.
    func generateMoreAdvice(for context: BestBaitContext) async {
        guard let recommendation = result?.recommendation,
              result?.key == context.key,
              case .onDeviceAppleIntelligence = result?.source,
              report == nil,
              !isGeneratingAdvice,
              adviceWorker != nil || session != nil else { return }

        let requestedGeneration = generation
        isGeneratingAdvice = true
        adviceError = nil
        defer {
            if isCurrent(requestedGeneration, key: context.key) {
                isGeneratingAdvice = false
            }
        }

        do {
            let generated: String
            if let adviceWorker {
                generated = try await adviceWorker(context, recommendation)
            } else if let session {
                let prompt = """
                Write a concise one- or two-sentence fishing report for the \
                selected forecast hour and bait pick below. Mention only named \
                conditions. Do not invent missing values or probability.

                Selected bait: \(recommendation.topBait), \
                \(recommendation.color)
                Technique: \(recommendation.technique)
                Depth: \(recommendation.depth)

                \(context.promptSummary)
                """
                generated = try await session.respond(to: prompt).content
            } else {
                return
            }

            guard isCurrent(requestedGeneration, key: context.key) else {
                return
            }
            report = generated
        } catch {
            guard isCurrent(requestedGeneration, key: context.key) else {
                return
            }
            adviceError = "Optional report unavailable: "
                + error.localizedDescription
        }
    }

    /// Free-text follow-up is deliberately separate from primary generation.
    /// The UI only exposes it after the user opens More Advice.
    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty,
              !isAnswering,
              !isGeneratingAdvice else { return }
        guard answerWorker != nil || canAnswer else { return }

        let requestedGeneration = generation
        let requestedKey = result?.key
        isAnswering = true
        defer {
            if Self.isCurrentGeneration(
                requestedGeneration,
                current: generation
            ) {
                isAnswering = false
            }
        }

        do {
            let answer: String
            if let answerWorker {
                answer = try await answerWorker(trimmed)
            } else if let session {
                answer = try await session.respond(to: trimmed).content
            } else {
                return
            }
            guard isCurrent(requestedGeneration, key: requestedKey) else {
                return
            }
            answers.append(QAPair(question: trimmed, answer: answer))
        } catch {
            guard isCurrent(requestedGeneration, key: requestedKey) else {
                return
            }
            answers.append(QAPair(
                question: trimmed,
                answer: "Couldn't answer: \(error.localizedDescription)"
            ))
        }
    }

    nonisolated static func isCurrentGeneration(
        _ requested: Int,
        current: Int
    ) -> Bool {
        requested == current
    }

    private func waitForCoalescedRequest(
        key: BaitContextKey,
        generation: Int
    ) async {
        await withCheckedContinuation { continuation in
            guard var current = inFlight,
                  current.key == key,
                  current.generation == generation else {
                continuation.resume()
                return
            }
            current.waiters.append(continuation)
            inFlight = current
        }
    }

    @discardableResult
    private func invalidate(for context: BestBaitContext?) -> Int {
        generation &+= 1
        finishInFlight()
        activeContext = context
        session = nil
        status = .idle
        result = nil
        report = nil
        adviceError = nil
        isGeneratingAdvice = false
        answers = []
        isAnswering = false
        return generation
    }

    private func finishInFlight(generation expected: Int? = nil) {
        guard let current = inFlight,
              expected == nil || current.generation == expected else {
            return
        }
        inFlight = nil
        current.waiters.forEach { $0.resume() }
    }

    private func generateStructuredRecommendation(
        for context: BestBaitContext
    ) async -> GenerationOutcome {
        do {
            let recommendation: BaitRecommendation
            if let recommendationWorker {
                recommendation = try await recommendationWorker(context)
            } else {
                let session = LanguageModelSession(
                    instructions: Self.instructions
                )
                self.session = session
                let prompt = """
                Recommend the single best bait for the selected forecast hour. \
                Return the structured recommendation before any optional prose. \
                Tie the concise reason only to named facts supplied below. Never \
                invent missing conditions or calibrated probability.

                \(context.promptSummary)
                """
                recommendation = try await session.respond(
                    to: prompt,
                    generating: BaitRecommendation.self
                ).content
            }
            return .success(recommendation, generatedAt: clock())
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func commit(
        _ outcome: GenerationOutcome,
        for context: BestBaitContext,
        generation requestedGeneration: Int
    ) {
        guard isCurrent(requestedGeneration, key: context.key) else { return }

        switch outcome {
        case .success(let recommendation, let generatedAt):
            result = BestBaitResult(
                key: context.key,
                recommendation: recommendation,
                source: .onDeviceAppleIntelligence(
                    generatedAt: generatedAt
                )
            )
            status = .ready
        case .failure(let message):
            publishFallback(
                for: context,
                generation: requestedGeneration,
                modelMessage: message
            )
        }
    }

    private func publishFallback(
        for context: BestBaitContext,
        generation requestedGeneration: Int,
        modelMessage: String
    ) {
        guard isCurrent(requestedGeneration, key: context.key),
              let recommendation = Self.fallbackRecommendation(
                for: context.species
              ) else { return }

        // The failure reason is intentionally not model-authored content and is
        // not promoted over the exact provenance label. Keeping the argument
        // documents that every unavailable/failure path converges here.
        _ = modelMessage
        result = BestBaitResult(
            key: context.key,
            recommendation: recommendation,
            source: .generalSpeciesGuidance
        )
        status = .ready
    }

    private func isCurrent(
        _ requestedGeneration: Int,
        key: BaitContextKey?
    ) -> Bool {
        guard Self.isCurrentGeneration(
            requestedGeneration,
            current: generation
        ) else { return false }
        guard let key else { return result == nil }
        return activeContext?.key == key
    }

    private static func fallbackRecommendation(
        for species: Species
    ) -> BaitRecommendation? {
        guard species != .all else { return nil }
        let profile = BaitProfile.profile(for: species)
        guard let bait = profile.baits.first,
              let technique = profile.techniques.first else { return nil }

        return BaitRecommendation(
            topBait: bait,
            color: "",
            technique: technique,
            depth: profile.habitatHint,
            confidence: 0,
            whyReason: "\(profile.habitatHint) \(profile.bestTimeOfDay)"
        )
    }

    private static let instructions = """
    You are an expert fishing guide. Give concise, practical advice grounded \
    only in the selected provider-neutral forecast hour supplied by BiteCast. \
    Match suggestions to the selected species and its water type. Prefer common, \
    widely available bait. Never invent conditions or calibrated probability.
    """

    private static var systemModelAvailability: ModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            .available
        case .unavailable(let reason):
            .unavailable(message(for: reason))
        @unknown default:
            .unavailable("On-device AI isn't available on this device.")
        }
    }

    private static func message(
        for reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            "This device doesn't support on-device AI."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in Settings for generated advice."
        case .modelNotReady:
            "The on-device model is still downloading."
        @unknown default:
            "On-device AI isn't available right now."
        }
    }
}
