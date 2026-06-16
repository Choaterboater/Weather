/// Result of identifying a fish from a photo. `matchedSpecies` is set when the
/// recognized name maps onto one of the app's tracked species.
struct FishIdentification: Equatable {
    let commonName: String
    let matchedSpecies: Species?
    let note: String
}
