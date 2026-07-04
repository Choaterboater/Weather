import Foundation
import Testing
import UIKit
@testable import BiteCast

/// Persistence safety for the catch log: a corrupt or unreadable file must
/// never be silently discarded and then overwritten by the next save.
@MainActor
@Suite("CatchLog persistence")
struct CatchLogTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatchLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func roundTripsEntriesThroughDisk() throws {
        let dir = try makeTempDirectory()
        let log = CatchLog(directory: dir)
        log.add(CatchEntry(species: .bass, bait: "spinnerbait"), photo: nil)

        let reloaded = CatchLog(directory: dir)
        #expect(reloaded.entries.count == 1)
        #expect(reloaded.entries.first?.bait == "spinnerbait")
    }

    @Test
    func corruptFileIsBackedUpBeforeAnythingOverwritesIt() throws {
        let dir = try makeTempDirectory()
        let corrupt = Data("{definitely not json".utf8)
        try corrupt.write(to: dir.appendingPathComponent("catches.json"))

        let log = CatchLog(directory: dir)
        #expect(log.entries.isEmpty)

        // The unreadable original must survive as a recovery file…
        let recovered = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("catches-recovered") }
        #expect(recovered.count == 1)
        #expect(try Data(contentsOf: try #require(recovered.first)) == corrupt)

        // …even after a new catch is saved over catches.json.
        log.add(CatchEntry(species: .bass, bait: "worm"), photo: nil)
        #expect(try Data(contentsOf: try #require(recovered.first)) == corrupt)
        let reloaded = CatchLog(directory: dir)
        #expect(reloaded.entries.count == 1)
    }

    @Test
    func oneMalformedEntryDoesNotDiscardTheRest() throws {
        let dir = try makeTempDirectory()
        let good = CatchEntry(species: .crappie, bait: "jig")
        let goodData = try JSONEncoder().encode([good])
        var text = try #require(String(data: goodData, encoding: .utf8))
        text = String(text.dropLast()) + #",{"id":42}]"#
        try Data(text.utf8).write(to: dir.appendingPathComponent("catches.json"))

        let log = CatchLog(directory: dir)
        #expect(log.entries.count == 1)
        #expect(log.entries.first?.bait == "jig")
    }

    @Test
    func removingAnEntryPersists() throws {
        let dir = try makeTempDirectory()
        let log = CatchLog(directory: dir)
        let entry = CatchEntry(species: .bass, bait: "chatterbait")
        log.add(entry, photo: nil)
        log.remove(entry)

        let reloaded = CatchLog(directory: dir)
        #expect(reloaded.entries.isEmpty)
    }
}
