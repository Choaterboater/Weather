import CoreLocation
import SwiftUI

struct MainTabView: View {
    @Environment(LocationManager.self) private var location
    @Environment(SpotStore.self) private var spots
    @Environment(WeatherStore.self) private var weather
    @Environment(TideService.self) private var tides
    @AppStorage("selectedTab") private var selectedTab: String = "weather"
    @State private var showSettings = false

    private var locationTitle: String {
        spots.selectedSpot?.name ?? location.placeName ?? "Weather"
    }

    /// Pull-to-refresh must bypass the stores' caches — a location nudge alone
    /// no longer re-keys the load tasks.
    private func refresh() async {
        location.refresh()
        guard let active = spots.selectedSpot?.location ?? location.location else { return }
        await weather.load(for: active, force: true)
        await tides.load(near: active, force: true)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Weather", systemImage: "cloud.sun.fill", value: "weather") {
                NavigationStack {
                    WeatherDashboardView()
                        .navigationTitle(locationTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .refreshable { await refresh() }
                }
            }
            Tab("Fishing", systemImage: "fish.fill", value: "fishing") {
                NavigationStack {
                    FishingView()
                        .navigationTitle("Fishing")
                        .navigationBarTitleDisplayMode(.inline)
                        .refreshable { await refresh() }
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { showSettings = true } label: {
                                    Image(systemName: "gearshape")
                                }
                                .accessibilityLabel("Settings")
                            }
                        }
                        .sheet(isPresented: $showSettings) { SettingsView() }
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
