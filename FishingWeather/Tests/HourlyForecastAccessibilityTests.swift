import Foundation
import Testing
@testable import BiteCast

@MainActor
@Suite("Hourly forecast accessibility")
struct HourlyForecastAccessibilityTests {
    @Test("Timeline hour identifiers use stable epoch seconds")
    func identifierUsesEpochSeconds() {
        let date = Date(timeIntervalSince1970: 1_800_000_000.75)

        #expect(
            HourlyForecastView.timelineAccessibilityIdentifier(for: date)
                == "timeline.hour.1800000000"
        )
    }

    @Test("Timeline hour identifiers safely handle invalid dates")
    func identifierHasSafeFallback() {
        let date = Date(timeIntervalSince1970: .infinity)

        #expect(
            HourlyForecastView.timelineAccessibilityIdentifier(for: date)
                == "timeline.hour.unavailable"
        )
    }

    @Test("Timeline hour values expose selection before weather details")
    func valueStartsWithSelectionState() {
        #expect(
            HourlyForecastView.timelineAccessibilityValue(
                isSelected: true,
                details: "78°, Clear"
            ) == "Selected, 78°, Clear"
        )
        #expect(
            HourlyForecastView.timelineAccessibilityValue(
                isSelected: false,
                details: "78°, Clear"
            ) == "Not selected, 78°, Clear"
        )
    }
}
