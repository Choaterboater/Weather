import CoreLocation
import SwiftUI

struct RootView: View {
    @Environment(LocationManager.self) private var location
    @Environment(WeatherStore.self) private var weather

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(location.placeName ?? "Fishing Weather")
                .navigationBarTitleDisplayMode(.inline)
        }
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
            LocationPromptView { location.requestPermission() }
        case .denied, .restricted:
            LocationDeniedView()
        default:
            WeatherDashboardView()
                .refreshable { location.refresh() }
        }
    }
}
