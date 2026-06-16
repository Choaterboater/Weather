import SwiftUI

struct MainTabView: View {
    @Environment(LocationManager.self) private var location
    @Environment(SpotStore.self) private var spots

    private var locationTitle: String {
        spots.selectedSpot?.name ?? location.placeName ?? "Weather"
    }

    var body: some View {
        TabView {
            Tab("Weather", systemImage: "cloud.sun.fill") {
                NavigationStack {
                    WeatherDashboardView()
                        .navigationTitle(locationTitle)
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
            Tab("Scout", systemImage: "camera.viewfinder") {
                NavigationStack {
                    ScoutView()
                        .navigationTitle("Scout the Water")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            Tab("Spots", systemImage: "mappin.and.ellipse") {
                NavigationStack {
                    SpotsView()
                        .navigationTitle("Spots")
                }
            }
            Tab("Log", systemImage: "book.closed.fill") {
                NavigationStack {
                    CatchLogView()
                        .navigationTitle("Catch Log")
                }
            }
        }
    }
}
