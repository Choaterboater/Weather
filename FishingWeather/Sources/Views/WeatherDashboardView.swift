import CoreLocation
import SwiftUI
import UIKit

struct WeatherDashboardView: View {
    @Environment(WeatherStore.self) private var weather
    @Environment(SpotStore.self) private var spots
    @Environment(LocationManager.self) private var location

    private let fixedNow: Date?

    init(fixedNow: Date? = nil) {
        self.fixedNow = fixedNow
    }

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
                } else if let error = weather.lastProviderError, !hasLiveWeather {
                    ErrorStateView(error: error)
                        .padding(.top, 80)
                } else if hasLiveWeather, let snapshot = weather.snapshot {
                    if !snapshot.alerts.isEmpty {
                        WeatherAlertsView(alerts: snapshot.alerts)
                    }
                    weatherStatus(snapshot)
                    if let error = weather.lastProviderError {
                        refreshNotice(error)
                    }
                    CurrentConditionsView(current: snapshot.current)
                    WindCard(
                        wind: snapshot.current.wind,
                        samples: snapshot.hourly.samples()
                    )
                    if !snapshot.hourly.isEmpty {
                        HourlyForecastView(hourly: snapshot.hourly)
                    }
                    if !snapshot.daily.isEmpty {
                        DailyForecastView(
                            daily: snapshot.daily,
                            timeZoneIdentifier: snapshot.timeZoneIdentifier
                        )
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
        .background(
            WeatherTheme.skyBackdrop(
                conditionText: weather.snapshot?.current.conditionText,
                symbolName: weather.snapshot?.current.symbolName
            )
        )
    }

    @ViewBuilder
    private func weatherStatus(_ snapshot: WeatherSnapshot) -> some View {
        if let fixedNow {
            weatherStatusContent(snapshot, now: fixedNow)
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                weatherStatusContent(snapshot, now: context.date)
            }
        }
    }

    static func sourcePresentation(
        for snapshot: WeatherSnapshot,
        now: Date,
        locale: Locale
    ) -> BiteTimeSourcePresentation {
        BiteTimeSourcePresentation.make(
            provenance: snapshot.provenance,
            now: now,
            timeZone: TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .gmt,
            locale: locale
        )
    }

    private func weatherStatusContent(
        _ snapshot: WeatherSnapshot,
        now: Date
    ) -> some View {
        let source = Self.sourcePresentation(
            for: snapshot,
            now: now,
            locale: .current
        )
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: source.symbolName)
                .foregroundStyle(snapshot.provenance.source == .cache ? Ink.brass : Ink.tide)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.chart)
                Text(weather.isLoading ? "Updating…" : source.freshness)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(Ink.chartDim)
                if let detail = source.detail {
                    Text(detail)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Ink.chartDim)
                }
            }
            Spacer()
            if weather.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 4)
    }

    private func refreshNotice(_ error: WeatherProviderError) -> some View {
        let presentation = BiteTimeErrorPresentation.make(for: error)
        return Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Update failed — showing the previous forecast")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                Text(presentation.message)
                    .font(.system(.caption, design: .rounded, weight: .medium))
            }
        } icon: {
            Image(systemName: presentation.symbolName)
        }
        .foregroundStyle(Ink.chart)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.brass.opacity(0.12), in: .rect(cornerRadius: 16))
    }
}

private struct ErrorStateView: View {
    let error: WeatherProviderError

    var body: some View {
        let presentation = BiteTimeErrorPresentation.make(for: error)
        ContentUnavailableView {
            Label(presentation.title, systemImage: presentation.symbolName)
        } description: {
            Text(presentation.message)
        }
    }
}
