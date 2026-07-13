import CoreLocation
import SwiftUI

/// Owns the forecast loader and drives `TripPlannerView`. This is what the
/// Fishing tab pushes; it fetches on appear and re-fetches when the spot or
/// species changes.
struct TripPlannerScreen: View {
    let location: CLLocation
    let species: Species
    let locationName: String

    @Environment(TideService.self) private var tides
    @Environment(AlertSettings.self) private var alertSettings
    @Environment(WeatherStore.self) private var weather
    @State private var loader = TripForecastLoader()
    @State private var retryID = 0

    var body: some View {
        TripPlannerView(
            outlook: loader.outlook,
            timeZone: forecastTimeZone,
            isLoading: loader.isLoading,
            errorMessage: loader.errorMessage,
            onRetry: { retryID += 1 }
        )
        .task(id: taskKey) { await load() }
    }

    private func load(force: Bool = false) async {
        let snapshot = matchingSnapshot
        let calendar = TripForecastLoader.forecastCalendar(for: snapshot)
        guard let outlook = await loader.load(
            for: location, species: species, locationName: locationName,
            snapshot: snapshot,
            tides: {
                await tides.weekTidesByDay(near: $0, calendar: calendar)
            },
            force: force
        ), !Task.isCancelled else { return }
        // Refresh scheduled bite alerts from the freshly loaded outlook. The
        // scheduler returns nothing when alerts are off, so this also clears.
        let alerts = BiteAlertScheduler.plan(from: outlook,
                                             preferences: alertSettings.preferences)
        await BiteAlertNotifier.reschedule(alerts)
    }

    private var taskKey: String {
        let request = TripForecastLoader.requestKey(
            location: location,
            species: species,
            locationName: locationName,
            snapshot: matchingSnapshot
        )
        return "\(request)|retry:\(retryID)"
    }

    private var matchingSnapshot: WeatherSnapshot? {
        weather.hasData(for: location) ? weather.snapshot : nil
    }

    private var forecastTimeZone: TimeZone {
        TripForecastLoader.forecastCalendar(for: matchingSnapshot).timeZone
    }
}

/// Explicit formatting for weekly forecast facts. SwiftUI's timezone
/// environment does not affect strings already produced by `Date.formatted`.
enum TripPlannerDateFormatting {
    static func timeRange(
        from start: Date,
        to end: Date,
        timeZone: TimeZone,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    static func weekday(
        _ date: Date,
        timeZone: TimeZone,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func fullDate(
        _ date: Date,
        timeZone: TimeZone,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

/// The Weekly Trip Planner screen: a ranked list of the coming week's best
/// fishing windows for the active spot, reached from the Fishing tab. Purely
/// presentational — the loader owns fetching and passes the outlook + state.
struct TripPlannerView: View {
    let outlook: WeekOutlook?
    var timeZone: TimeZone = .current
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal)
                .padding(.bottom, 24)
        }
        .background(Ink.backdrop)
        .navigationTitle("Plan the Week")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        if let outlook, !outlook.isEmpty {
            GlassCardStack(spacing: 12) {
                header(outlook)
                ForEach(outlook.windows) { window in
                    ScoredWindowRow(window: window, timeZone: timeZone)
                }
                legend
            }
        } else if isLoading {
            ProgressView("Scoring the week…")
                .padding(.top, 80)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Couldn't load the forecast", systemImage: "cloud.slash")
            } description: {
                Text(errorMessage)
            } actions: {
                if let onRetry {
                    Button("Try again", action: onRetry)
                        .buttonStyle(.glassProminent)
                }
            }
            .padding(.top, 60)
        } else {
            ContentUnavailableView(
                "No strong windows this week",
                systemImage: "calendar.badge.clock",
                description: Text("Conditions look flat. Check back as the forecast firms up.")
            )
            .padding(.top, 60)
        }
    }

    private func header(_ outlook: WeekOutlook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Best This Week")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(Ink.chart)
            Text(outlook.locationName)
                .instrumentLabel(Ink.brass)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(filled: true, "High confidence")
            legendItem(filled: false, "Forecast further out")
            Spacer()
        }
        .padding(.top, 4)
        .padding(.horizontal, 4)
    }

    private func legendItem(filled: Bool, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .strokeBorder(Ink.chartDim, lineWidth: filled ? 0 : 1.2)
                .background(Circle().fill(filled ? Ink.chartDim : .clear))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Ink.chartDim)
        }
    }
}

private struct ScoredWindowRow: View {
    @Environment(\.locale) private var locale

    let window: ScoredWindow
    let timeZone: TimeZone

    private var timeRange: String {
        TripPlannerDateFormatting.timeRange(
            from: window.start,
            to: window.end,
            timeZone: timeZone,
            locale: locale
        )
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(TripPlannerDateFormatting.weekday(
                            window.start,
                            timeZone: timeZone,
                            locale: locale
                        ))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.chart)
                        periodPill
                    }
                    Text(timeRange)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
                    scoreBar
                    if !window.factors.isEmpty {
                        Text(window.factors.joined(separator: " · "))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    }
                }

                Spacer(minLength: 8)

                VStack(spacing: 4) {
                    Text("\(window.score)")
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Ink.band(for: window.score))
                    confidenceTag
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(TripPlannerDateFormatting.fullDate(window.start, timeZone: timeZone, locale: locale)), \(timeRange), score \(window.score), \(window.confidence == .high ? "high" : "lower") confidence")
    }

    private var periodPill: some View {
        Text(window.period.rawValue)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Ink.abyss)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(window.period == .major ? Ink.bite : Ink.brass, in: .capsule)
    }

    private var scoreBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.hullLine)
                Capsule()
                    .fill(Ink.band(for: window.score))
                    .frame(width: max(4, geo.size.width * CGFloat(window.score) / 100))
            }
        }
        .frame(height: 5)
    }

    private var confidenceTag: some View {
        HStack(spacing: 4) {
            Circle()
                .strokeBorder(Ink.chartDim, lineWidth: window.confidence == .high ? 0 : 1)
                .background(Circle().fill(window.confidence == .high ? Ink.chartDim : .clear))
                .frame(width: 6, height: 6)
            Text(window.confidence == .high ? "HIGH" : "LOW")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(Ink.chartDim)
        }
    }
}
