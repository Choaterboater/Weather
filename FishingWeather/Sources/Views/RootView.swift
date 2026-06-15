import CoreLocation
import SwiftUI

struct RootView: View {
    @Environment(LocationManager.self) private var location
    @Environment(WeatherStore.self) private var weather

    var body: some View {
        content
            .task(id: location.location?.coordinate.latitude) {
                if let coordinate = location.location {
                    await weather.load(for: coordinate)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch location.authorizationStatus {
        case .notDetermined:
            NavigationStack {
                LocationPromptView { location.requestPermission() }
            }
        case .denied, .restricted:
            NavigationStack {
                LocationDeniedView()
            }
        default:
            MainTabView()
        }
    }
}
