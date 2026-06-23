import SwiftUI

struct MainTabView: View {
    @Environment(LocationManager.self) private var location
    @Environment(SpotStore.self) private var spots
    @AppStorage("selectedTab") private var selectedTab: String = "weather"

    private var locationTitle: String {
        spots.selectedSpot?.name ?? location.placeName ?? "Weather"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Weather", systemImage: "cloud.sun.fill", value: "weather") {
                NavigationStack {
                    WeatherDashboardView()
                        .navigationTitle(locationTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .refreshable { location.refresh() }
                }
            }
            Tab("Fishing", systemImage: "fish.fill", value: "fishing") {
                NavigationStack {
                    FishingView()
                        .navigationTitle("Fishing")
                        .navigationBarTitleDisplayMode(.inline)
                        .refreshable { location.refresh() }
                }
            }
            Tab("Spots", systemImage: "mappin.and.ellipse", value: "spots") {
                NavigationStack {
                    SpotsView()
                        .navigationTitle("Spots")
                }
            }
            Tab("Guide", systemImage: "book.pages.fill", value: "guide") {
                NavigationStack {
                    SpeciesGuideView()
                        .navigationTitle("Species Guide")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            Tab("Log", systemImage: "book.closed.fill", value: "log") {
                NavigationStack {
                    CatchLogView()
                        .navigationTitle("Catch Log")
                }
            }
            Tab("Scout", systemImage: "camera.viewfinder", value: "scout") {
                NavigationStack {
                    ScoutView()
                        .navigationTitle("Scout the Water")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }
}
