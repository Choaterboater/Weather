import FoundationModels

/// Structured "read the water" guidance from a photo of a fishing spot.
@Generable
struct WaterScoutReport: Equatable {
    @Guide(description: "How promising this water looks for the target species, 0 to 100", .range(0...100))
    let rating: Int

    @Guide(description: "The single best place to cast, described by its location and feature in the scene")
    let bestSpot: String

    @Guide(description: "Fish-holding structure or cover suggested by the scene (cover, edges, current, depth changes)")
    let structure: String

    @Guide(description: "How to approach and fish this water for the species")
    let approach: String

    @Guide(description: "One short caution or extra tip")
    let notes: String
}
