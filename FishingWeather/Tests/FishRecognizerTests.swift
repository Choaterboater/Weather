import Testing
import UIKit
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

    @MainActor
    @Test("identify waits until the active worker commits its result")
    func identifyWaitsForActiveWorker() async {
        let expected = FishIdentification(
            commonName: "Largemouth Bass",
            matchedSpecies: .bass,
            note: "Test worker"
        )
        let recognizer = FishRecognizer(worker: { _ in
            try await Task.sleep(for: .milliseconds(50))
            return expected
        })

        await recognizer.identify(image: UIImage())

        #expect(recognizer.status == .ready)
        #expect(recognizer.result == expected)
    }
}
