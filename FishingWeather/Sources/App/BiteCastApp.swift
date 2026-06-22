import SwiftUI

@main
struct BiteCastApp: App {
    @State private var locationManager = LocationManager()
    @State private var weatherStore = WeatherStore()
    @State private var spotStore = SpotStore()
    @State private var catchLog = CatchLog()
    @State private var regulationStore = RegulationStore()
    @State private var tideService = TideService()
    @State private var spotCatalog = CuratedSpotCatalog()
    @State private var osmClient = OpenStreetMapClient()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(locationManager)
                .environment(weatherStore)
                .environment(spotStore)
                .environment(catchLog)
                .environment(regulationStore)
                .environment(tideService)
                .environment(spotCatalog)
                .environment(osmClient)
        }
    }
}
