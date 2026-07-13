import Testing
@testable import BiteCast

@Suite("Navigation contract")
struct NavigationContractTests {
    @Test func defaultsToBiteTime() {
        #expect(AppDestination.defaultDestination == .biteTime)
    }

    @Test func permanentDestinationsAreStable() {
        #expect(
            AppDestination.allCases.map(\.rawValue)
                == ["community", "map", "biteTime", "you"]
        )
    }

    @Test(arguments: [
        (stored: "weather", expected: AppDestination.biteTime),
        (stored: "fishing", expected: AppDestination.biteTime),
        (stored: "spots", expected: AppDestination.map),
        (stored: "guide", expected: AppDestination.you),
        (stored: "log", expected: AppDestination.you),
        (stored: "scout", expected: AppDestination.you),
        (stored: "unknown", expected: AppDestination.biteTime),
    ])
    func legacySelectionsMigrateToPermanentDestinations(
        stored: String,
        expected: AppDestination
    ) {
        #expect(AppDestination.migrating(storedValue: stored) == expected)
    }
}
