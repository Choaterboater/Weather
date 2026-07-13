import Foundation
import Testing
@testable import BiteCast

@Suite("Location descriptor")
struct LocationDescriptorTests {
    @Test func composesCityAndState() {
        let value = LocationDescriptor.make(city: " Inlet Beach ", stateCode: "fl", featureName: nil)
        #expect(value.displayName == "Inlet Beach, FL")
    }

    @Test func rejectsCoordinateFeatureName() {
        let value = LocationDescriptor.make(
            city: nil,
            stateCode: "FL",
            featureName: "30.2938° N, 86.0049° W"
        )
        #expect(value.displayName == "Current Location")
        #expect(value.subtitle == "FL")
    }

    @Test func preservesNamedFeature() {
        let value = LocationDescriptor.make(city: nil, stateCode: "FL", featureName: "Phillips Inlet")
        #expect(value.displayName == "Phillips Inlet")
        #expect(value.subtitle == "FL")
    }
}
