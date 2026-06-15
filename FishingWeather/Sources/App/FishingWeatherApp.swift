import SwiftUI

@main
struct FishingWeatherApp: App {
    @State private var locationManager = LocationManager()
    @State private var weatherStore = WeatherStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(locationManager)
                .environment(weatherStore)
        }
    }
}
