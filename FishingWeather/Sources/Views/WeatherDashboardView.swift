import CoreLocation
import SwiftUI
import UIKit

struct WeatherDashboardView: View {
    @Environment(WeatherStore.self) private var weather
    @Environment(SpotStore.self) private var spots
    @Environment(LocationManager.self) private var location

    private var activeLocation: CLLocation? {
        spots.selectedSpot?.location ?? location.location
    }

    private var hasLiveWeather: Bool {
        guard let activeLocation else { return false }
        return weather.hasData(for: activeLocation)
    }

    var body: some View {
        ScrollView {
            GlassCardStack(spacing: 20) {
                if activeLocation == nil {
                    ContentUnavailableView(
                        "Locating…",
                        systemImage: "location",
                        description: Text("Waiting for a GPS fix to load the forecast.")
                    )
                    .padding(.top, 80)
                } else if weather.isLoading && !hasLiveWeather {
                    ProgressView("Loading weather…")
                        .padding(.top, 80)
                } else if weather.errorMessage != nil, !hasLiveWeather {
                    ErrorStateView()
                        .padding(.top, 80)
                } else if hasLiveWeather {
                    if !weather.alerts.isEmpty {
                        WeatherAlertsView(alerts: weather.alerts)
                    }
                    if let current = weather.current {
                        CurrentConditionsView(current: current)
                        WindCard(
                            current: current,
                            samples: weather.hourly?.samples() ?? []
                        )
                    }
                    if let hourly = weather.hourly {
                        HourlyForecastView(hourly: hourly)
                    }
                    if let daily = weather.daily {
                        DailyForecastView(daily: daily)
                    }
                } else {
                    ContentUnavailableView(
                        "No weather yet",
                        systemImage: "cloud",
                        description: Text("Pull to refresh once you have a location.")
                    )
                    .padding(.top, 80)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background {
            WeatherTheme.skyBackdrop(for: hasLiveWeather ? weather.current?.condition : nil)
        }
    }
}

private struct ErrorStateView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Weather unavailable", systemImage: "cloud.bolt.rain")
        } description: {
            Text("BiteCast couldn't reach the weather service. Pull down to refresh, or try again once you're back online.")
        }
    }
}
