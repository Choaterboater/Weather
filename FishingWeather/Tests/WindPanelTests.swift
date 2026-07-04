import Testing
@testable import BiteCast

@Suite("Wind descriptor")
struct WindPanelTests {
    @Test("Thresholds map speed to the right on-the-water read", arguments: [
        (0.0, "Calm"), (4.9, "Calm"),
        (5.0, "Light breeze"), (9.9, "Light breeze"),
        (10.0, "Breezy"), (14.9, "Breezy"),
        (15.0, "Windy"), (19.9, "Windy"),
        (20.0, "Strong"), (45.0, "Strong"),
    ])
    func descriptorThresholds(mph: Double, expectedPrefix: String) {
        #expect(WindPanel.descriptor(forMph: mph).hasPrefix(expectedPrefix))
    }
}
