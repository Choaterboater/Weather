import SwiftUI

struct MainTabView: View {
    @Environment(LocationManager.self) private var location

    var body: some View {
        TabView {
            Tab("Weather", systemImage: "cloud.sun.fill") {
                NavigationStack {
                    WeatherDashboardView()
                        .navigationTitle(location.placeName ?? "Weather")
                        .navigationBarTitleDisplayMode(.inline)
                        .refreshable { location.refresh() }
                }
            }
            Tab("Fishing", systemImage: "fish.fill") {
                NavigationStack {
                    FishingView()
                        .navigationTitle("Fishing")
                        .navigationBarTitleDisplayMode(.inline)
                        .refreshable { location.refresh() }
                }
            }
        }
    }
}
