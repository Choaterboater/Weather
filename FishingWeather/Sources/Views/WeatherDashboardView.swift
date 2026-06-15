import SwiftUI

struct WeatherDashboardView: View {
    @Environment(WeatherStore.self) private var weather

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if weather.isLoading && weather.current == nil {
                    ProgressView("Loading weather…")
                        .padding(.top, 80)
                } else if let message = weather.errorMessage, weather.current == nil {
                    ErrorStateView(message: message)
                        .padding(.top, 80)
                } else {
                    if !weather.alerts.isEmpty {
                        WeatherAlertsView(alerts: weather.alerts)
                    }
                    if let current = weather.current {
                        CurrentConditionsView(current: current)
                    }
                    if let hourly = weather.hourly {
                        HourlyForecastView(hourly: hourly)
                    }
                    if let daily = weather.daily {
                        DailyForecastView(daily: daily)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.35), .cyan.opacity(0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

private struct ErrorStateView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't load weather", systemImage: "cloud.bolt.rain")
        } description: {
            Text(message)
        }
    }
}
