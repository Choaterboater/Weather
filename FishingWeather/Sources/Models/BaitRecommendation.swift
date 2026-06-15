import FoundationModels

/// Structured output for the AI bait engine. `@Generable` makes the on-device
/// model fill these fields directly instead of returning free-form text.
@Generable
struct BaitRecommendation: Equatable {
    @Guide(description: "The single best bait or lure to throw right now")
    let topBait: String

    @Guide(description: "Recommended color or pattern for the bait")
    let color: String

    @Guide(description: "How to fish it — retrieve, rig, or presentation in a few words")
    let technique: String

    @Guide(description: "Target water depth, e.g. '2-4 ft' or 'near bottom'")
    let depth: String

    @Guide(description: "Confidence in this recommendation, from 0 to 100", .range(0...100))
    let confidence: Int

    @Guide(description: "One or two sentences on why, tied to today's conditions")
    let whyReason: String
}
