import Testing
@testable import BiteCast

@Suite("CuratedSpotCatalog IDs")
struct CuratedSpotIDTests {
    @Test
    func stableIDsAreDeterministic() {
        let a = CuratedSpotCatalog.stableID(name: "Grayton Beach Surf", latitude: 30.328, longitude: -86.157)
        let b = CuratedSpotCatalog.stableID(name: "Grayton Beach Surf", latitude: 30.328, longitude: -86.157)
        let c = CuratedSpotCatalog.stableID(name: "Western Lake (30A)", latitude: 30.302, longitude: -86.157)
        #expect(a == b)
        #expect(a != c)
    }
}
