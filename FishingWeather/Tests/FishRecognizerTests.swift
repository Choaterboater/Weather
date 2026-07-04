import Testing
@testable import BiteCast

@Suite("FishRecognizer matching")
struct FishRecognizerTests {
    @Test
    func matchesDisplayNames() {
        #expect(FishRecognizer.matchSpecies(in: "Speckled Trout") == .speckledTrout)
        #expect(FishRecognizer.matchSpecies(in: "Mangrove Snapper") == .mangroveSnapper)
        #expect(FishRecognizer.matchSpecies(in: "Largemouth Bass") == .bass)
    }

    @Test
    func matchesCommonAliases() {
        #expect(FishRecognizer.matchSpecies(in: "Red Drum") == .redfish)
        #expect(FishRecognizer.matchSpecies(in: "Spotted Seatrout") == .speckledTrout)
        #expect(FishRecognizer.matchSpecies(in: "Gray Snapper") == .mangroveSnapper)
    }
}
