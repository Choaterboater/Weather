import Foundation
import Observation

/// Loads bundled state-by-state regulation JSON and answers lookups by species
/// and state. Curated, hand-typed from state agency rules — `lastVerifiedDate`
/// and `sourceURL` per state tell the user how stale the data may be.
///
/// JSON files live at `Sources/Support/Regulations/<STATE>.json` and are bundled
/// as resources. New states are added by dropping a new file in that folder.
@MainActor
@Observable
final class RegulationStore {
    private(set) var states: [String: StateRegulations] = [:]

    init() {
        loadAll()
    }

    var loadedStateCodes: [String] {
        states.keys.sorted()
    }

    /// The regulation for `species` in `stateCode` on `date`, if any is on file.
    /// Returns `nil` if the state isn't loaded or the species isn't covered there.
    func regulation(for species: Species, in stateCode: String, on date: Date = .now) -> Regulation? {
        guard let state = states[stateCode.uppercased()] else { return nil }
        return state.regulations.first { $0.speciesId == species.rawValue }
    }

    /// Metadata (source URL + verified date) for a given state's ruleset.
    func stateInfo(_ stateCode: String) -> StateRegulations? {
        states[stateCode.uppercased()]
    }

    /// All species we have regulations for in a given state, optionally filtered
    /// by water type. Useful for "what can I catch here" listings.
    func species(in stateCode: String, waterType: WaterType? = nil) -> [Species] {
        guard let state = states[stateCode.uppercased()] else { return [] }
        return state.regulations
            .filter { waterType == nil || $0.waterType == waterType }
            .compactMap { Species(rawValue: $0.speciesId) }
    }

    private func loadAll() {
        let bundle = Bundle.main
        // Xcode often flattens resources to the bundle root, so try the Regulations/
        // subdir first and fall back to root, then de-duplicate.
        let nested = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Regulations") ?? []
        let flat = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        var seen = Set<URL>()
        let decoder = JSONDecoder()
        for url in nested + flat where seen.insert(url).inserted {
            guard let data = try? Data(contentsOf: url),
                  let state = try? decoder.decode(StateRegulations.self, from: data) else {
                continue
            }
            states[state.stateCode.uppercased()] = state
        }
    }
}
