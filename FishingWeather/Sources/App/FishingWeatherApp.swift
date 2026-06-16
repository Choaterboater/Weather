import SwiftUI

@main
struct FishingWeatherApp: App {
    @State private var locationManager = LocationManager()
    @State private var weatherStore = WeatherStore()
    @State private var spotStore = SpotStore()
    @State private var catchLog = CatchLog()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(locationManager)
                .environment(weatherStore)
                .environment(spotStore)
                .environment(catchLog)
        }
    }
}
