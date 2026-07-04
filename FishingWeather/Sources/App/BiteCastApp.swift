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
    @State private var inaturalist = INaturalistClient()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if CommandLine.arguments.contains("-uiPreview") {
                DebugPreviewHost()
                    .preferredColorScheme(.dark)
            } else {
                appContent
            }
            #else
            appContent
            #endif
        }
    }

    private var appContent: some View {
        RootView()
            // The marine-instrument identity is a dark theme; lock the app to
            // dark so bare text on the abyss backdrop stays legible and the
            // glass cards render as dark instrument panels regardless of the
            // device's system appearance.
            .preferredColorScheme(.dark)
            .environment(locationManager)
            .environment(weatherStore)
            .environment(spotStore)
            .environment(catchLog)
            .environment(regulationStore)
            .environment(tideService)
            .environment(spotCatalog)
            .environment(osmClient)
            .environment(inaturalist)
    }
}
