import Foundation
import Testing
@testable import BiteCast

@Suite("OpenStreetMap parsing")
struct OpenStreetMapClientTests {
    @Test("Node and way IDs with the same number remain distinct")
    func nodeAndWayIDsAreNamespaced() throws {
        let data = Data(
            """
            {
              "elements": [
                {
                  "type": "node",
                  "id": 42,
                  "lat": 27.7600,
                  "lon": -82.6400,
                  "tags": { "amenity": "boat_ramp", "name": "Node Ramp" }
                },
                {
                  "type": "way",
                  "id": 42,
                  "center": { "lat": 27.7700, "lon": -82.6500 },
                  "tags": { "amenity": "boat_ramp", "name": "Way Ramp" }
                }
              ]
            }
            """.utf8
        )

        let pins = try OpenStreetMapClient.pins(from: data)

        #expect(pins.count == 2)
        #expect(Set(pins.map(\.id)).count == 2)
        #expect(Set(pins.map(\.id)) == ["node/42", "way/42"])
    }
}
