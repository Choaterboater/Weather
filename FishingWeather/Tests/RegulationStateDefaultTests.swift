import Testing
@testable import BiteCast

/// The regulations picker used to default to the alphabetically-first loaded
/// state (Alabama) whenever no saved spot was active, ignoring the device's
/// real location. These pin the corrected precedence: spot state, then device
/// state, then first available.
@Suite("Regulation default state")
struct RegulationStateDefaultTests {
    // The six states bundled today, in the sorted order loadedStateCodes yields.
    let available = ["AL", "FL", "GA", "LA", "TN", "TX"]
    func hasData(_ code: String) -> Bool { available.contains(code) }

    private func resolve(spot: String?, device: String?) -> String? {
        RegulationStore.resolveDefaultState(
            spotState: spot, deviceState: device, available: available, hasData: hasData
        )
    }

    @Test("Device state wins when no spot is selected (the bug)")
    func deviceStateUsedWithoutSpot() {
        // Previously returned "AL" (available.first) regardless of location.
        #expect(resolve(spot: nil, device: "FL") == "FL")
    }

    @Test("A saved spot's state takes precedence over the device")
    func spotStateBeatsDevice() {
        #expect(resolve(spot: "GA", device: "FL") == "GA")
    }

    @Test("Falls back to first available when device state has no data")
    func unsupportedDeviceStateFallsBack() {
        // Device in California, which we don't cover yet.
        #expect(resolve(spot: nil, device: "CA") == "AL")
    }

    @Test("Falls back to first available when nothing is known")
    func noSignalFallsBack() {
        #expect(resolve(spot: nil, device: nil) == "AL")
    }

    @Test("A spot with an unsupported state defers to the device")
    func unsupportedSpotStateDefersToDevice() {
        #expect(resolve(spot: "CA", device: "FL") == "FL")
    }

    @Test("Returns nil only when no states are loaded")
    func nilWhenNothingLoaded() {
        #expect(
            RegulationStore.resolveDefaultState(
                spotState: nil, deviceState: "FL", available: [], hasData: { _ in false }
            ) == nil
        )
    }
}
