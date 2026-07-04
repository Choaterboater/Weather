import Testing
@testable import BiteCast

/// Guards that every bundled regulation JSON decodes into the model and that a
/// few high-stakes numbers survive the trip. If a JSON file is malformed,
/// RegulationStore silently skips it — so a missing state here means broken data.
@MainActor
@Suite("Bundled regulations")
struct RegulationBundleTests {
    @Test("All expected states load and decode")
    func allStatesLoad() {
        let loaded = Set(RegulationStore().loadedStateCodes)
        for code in ["AL", "FL", "GA", "LA", "TN", "TX", "SC", "NC", "MS"] {
            #expect(loaded.contains(code), "missing or undecodable: \(code)")
        }
    }

    @Test("Newly added states expose their confirmed limits")
    func newStateSpotChecks() {
        let store = RegulationStore()

        // SC red drum — the July 2026 slot (18–25", 1/day).
        let scRed = store.regulation(for: .redfish, in: "SC")
        #expect(scRed?.minSizeInches == 18)
        #expect(scRed?.maxSizeInches == 25)
        #expect(scRed?.dailyBagLimit == 1)

        // NC southern flounder — harvest closed (0 bag, always closed).
        let ncFlounder = store.regulation(for: .flounder, in: "NC")
        #expect(ncFlounder?.dailyBagLimit == 0)
        #expect(ncFlounder?.isClosed(on: .now) == true)

        // MS spotted seatrout — 15" minimum, 15/day.
        let msTrout = store.regulation(for: .speckledTrout, in: "MS")
        #expect(msTrout?.minSizeInches == 15)
        #expect(msTrout?.dailyBagLimit == 15)
    }
}
