import CoreLocation
import Testing
@testable import BiteCast

@Suite("Location state")
struct LocationStateTests {
    @Test("Denied location still permits saved-spot access")
    func deniedLocationStillEntersWhenSavedSpotsExist() {
        #expect(RootView.canEnterMainContent(status: .denied, hasSavedSpots: true))
        #expect(!RootView.canEnterMainContent(status: .denied, hasSavedSpots: false))
    }

    @Test("Only the current coordinate may apply a reverse-geocode result")
    func onlyCurrentCoordinateMayApplyGeocodeResult() {
        let requested = CLLocationCoordinate2D(latitude: 27.1, longitude: -82.1)
        let current = CLLocation(latitude: 28.1, longitude: -83.1)

        #expect(!LocationManager.isCurrentGeocode(requested, current: current))
        #expect(LocationManager.isCurrentGeocode(current.coordinate, current: current))
    }

    @MainActor
    @Test("A canceled stale geocode cannot restore labels for an older coordinate")
    func staleGeocodeCannotRestoreOldLabels() async {
        let manager = LocationManager(reverseGeocoder: { location in
            if location.coordinate.latitude == 27.1 {
                try? await Task.sleep(for: .milliseconds(100))
                return LocationManager.GeocodeResult(placeName: "Old Place", stateCode: "FL")
            }
            return nil
        })
        manager.placeName = "Existing Place"
        manager.administrativeArea = "FL"

        manager.acceptLocation(CLLocationCoordinate2D(latitude: 27.1, longitude: -82.1))
        await Task.yield()
        manager.acceptLocation(CLLocationCoordinate2D(latitude: 28.1, longitude: -83.1))

        #expect(manager.placeName == nil)
        #expect(manager.administrativeArea == nil)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(manager.location?.coordinate.latitude == 28.1)
        #expect(manager.placeName == nil)
        #expect(manager.administrativeArea == nil)
    }
}
