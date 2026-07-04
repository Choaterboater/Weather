import Foundation
import CoreLocation
import SwiftUI
import WeatherKit

struct FishingView: View {
    @Environment(WeatherStore.self) private var weather
    @Environment(SpotStore.self) private var spots
    @Environment(LocationManager.self) private var location
    @Environment(TideService.self) private var tides
    @AppStorage("selectedSpecies") private var species: Species = .all
    @State private var engine = BaitEngine()

    /// True when the active spot is saltwater, or unknown and tide data came back.
    private var showsTides: Bool {
        if let waterType = spots.selectedSpot?.waterType {
            return waterType != .freshwater
        }
        // Unknown water type: trust whether NOAA found a nearby station.
        return tides.station != nil
    }

    var body: some View {
        ScrollView {
            GlassCardStack(spacing: 20) {
                SpeciesPicker(selection: $species)
                    .padding(.top, 4)

                if let conditions = weather.conditions {
                    FishingScoreCard(score: FishingScorer.score(
                        conditions: conditions,
                        species: species,
                        // allEvents spans yesterday–tomorrow so late-evening
                        // scoring sees the next event after midnight.
                        tideEvents: showsTides ? tides.allEvents : []
                    ))
                    SpeciesFocusCard(species: species)
                    BaitEngineView(conditions: conditions, species: species, engine: engine)
                    BiteWindowsCard(conditions: conditions)
                    if showsTides {
                        TideCard(
                            events: tides.events,
                            samples: tides.samples,
                            stationName: tides.station?.name,
                            distanceMiles: tides.distanceMiles,
                            isLoading: tides.isLoading
                        )
                    }
                    PressureCard(reading: conditions.pressure, samples: hourlySamples)
                    SolunarDetailsCard(conditions: conditions)
                } else if weather.isLoading {
                    ProgressView("Reading conditions…")
                        .padding(.top, 80)
                } else if let message = weather.errorMessage {
                    SpeciesFocusCard(species: species)
                    if let loc = activeLocation, let cachedPressure = WeatherSnapshots.cachedPressure(for: loc) {
                        CachedPressureCard(reading: cachedPressure, samples: hourlySamples)
                    }
                    ContentUnavailableView {
                        Label("Couldn't load conditions", systemImage: "wifi.slash")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") {
                            Task {
                                if let activeLocation {
                                    await weather.load(for: activeLocation, force: true)
                                }
                            }
                        }
                        .buttonStyle(.glassProminent)
                    }
                    .padding(.top, 8)
                } else if let loc = activeLocation, let cachedPressure = WeatherSnapshots.cachedPressure(for: loc) {
                    SpeciesFocusCard(species: species)
                    CachedPressureCard(reading: cachedPressure, samples: hourlySamples)
                    ContentUnavailableView(
                        "Live weather unavailable",
                        systemImage: "cloud.slash",
                        description: Text("Showing cached conditions from your last session.")
                    )
                    .padding(.top, 8)
                } else {
                    SpeciesFocusCard(species: species)
                    ContentUnavailableView(
                        "No conditions yet",
                        systemImage: "fish",
                        description: Text("Weather data is needed to compute fishing windows.")
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [.teal.opacity(0.35), .green.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .task(id: activeLocationKey) {
            if let coordinate = activeLocation {
                await tides.load(near: coordinate)
            }
        }
        .onChange(of: species) { engine.reset() }
        .sensoryFeedback(.selection, trigger: species)
    }

    private var activeLocation: CLLocation? {
        spots.selectedSpot?.location ?? location.location
    }

    /// Re-keys the tide task whenever the active spot or GPS coordinate changes.
    private var activeLocationKey: String {
        guard let coord = activeLocation?.coordinate else { return "none" }
        return "\(coord.latitude.rounded(toPlaces: 2)),\(coord.longitude.rounded(toPlaces: 2))"
    }

    private var hourlySamples: [HourSample] {
        if let live = weather.hourly?.samples(), !live.isEmpty {
            return live
        }
        if let loc = activeLocation {
            return WeatherSnapshots.cachedSamples(for: loc)
        }
        return []
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}

// MARK: - Cached pressure fallback

/// Shown when live weather is unavailable but an offline snapshot exists.
private struct CachedPressureCard: View {
    let reading: PressureReading
    var samples: [HourSample] = []

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(reading.pressure.formatted(.measurement(width: .abbreviated, usage: .barometric)))
                        .font(.title.weight(.semibold))
                        .contentTransition(.numericText())
                    Label(reading.tendency.label, systemImage: reading.tendency.symbolName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(reading.tendency == .falling ? .green : .secondary)
                    if let perHour = reading.changePerHour, abs(perHour) >= 0.1 {
                        Text(String(format: "%+.1f hPa/hr", perHour))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(reading.tendency.fishingNote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !samples.isEmpty {
                    PressureTrendChart(samples: samples, now: .now)
                        .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Species focus

private struct SpeciesFocusCard: View {
    let species: Species

    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "fish.fill")
                    .font(.title3)
                    .foregroundStyle(species.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(species == .all ? "All species" : species.displayName)
                        .font(.headline)
                    Text(species.focusNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Bite windows

private struct BiteWindowsCard: View {
    let conditions: FishingConditions

    @State private var reminderState: ReminderState = .none

    private enum ReminderState { case none, scheduled, tooLate }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Bite Windows", systemImage: "timer")
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    headline
                    if conditions.windows.isEmpty {
                        Text("No solunar windows for today (moonrise/moonset unavailable).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        BiteWindowsTimeline(windows: conditions.windows, now: .now)
                        ForEach(conditions.windows) { window in
                            BiteWindowRow(window: window)
                        }
                        reminderControl
                    }
                }
            }
        }
        // The card outlives its windows (weather refresh, spot switch): a
        // "Reminder set" badge must not survive for a window it never covered.
        .onChange(of: conditions.nextWindow()?.start) { reminderState = .none }
    }

    @ViewBuilder
    private var reminderControl: some View {
        if let next = conditions.nextWindow() {
            Group {
                switch reminderState {
                case .none:
                    Button {
                        Task {
                            let ok = await BiteWindowNotifier.scheduleReminder(for: next)
                            reminderState = ok ? .scheduled : .tooLate
                        }
                    } label: {
                        Label("Remind me 30 min before", systemImage: "bell")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                case .scheduled:
                    Label("Reminder set", systemImage: "bell.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: reminderState == .scheduled)
                        .transition(.scale.combined(with: .opacity))
                case .tooLate:
                    Label("That window is too soon to remind", systemImage: "bell.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.snappy, value: reminderState)
            .sensoryFeedback(trigger: reminderState) { _, newValue in
                switch newValue {
                case .scheduled: .success
                case .tooLate: .warning
                case .none: nil
                }
            }
        }
    }

    @ViewBuilder
    private var headline: some View {
        if let active = conditions.activeWindow() {
            Label {
                Text("\(active.period.rawValue) window now — until \(active.end.formatted(date: .omitted, time: .shortened))")
                    .font(.headline)
            } icon: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }
        } else if let next = conditions.nextWindow() {
            Label {
                Text("Next: \(next.period.rawValue) at \(next.peak.formatted(date: .omitted, time: .shortened))")
                    .font(.headline)
            } icon: {
                Image(systemName: "clock.badge")
                    .foregroundStyle(.teal)
            }
        } else {
            Text("Today's feeding windows")
                .font(.headline)
        }
    }
}

private struct BiteWindowRow: View {
    let window: BiteWindow

    private var isActive: Bool { window.isActive(at: .now) }

    private var timeRange: String {
        let start = window.start.formatted(date: .omitted, time: .shortened)
        let end = window.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(window.period.rawValue)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(window.period == .major ? .green.opacity(0.25) : .teal.opacity(0.2))
                .clipShape(.capsule)

            VStack(alignment: .leading, spacing: 2) {
                Text(timeRange)
                    .font(.subheadline.weight(.medium))
                Text(window.cause)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Pressure

private struct PressureCard: View {
    let reading: PressureReading
    var samples: [HourSample] = []

    private var pressureText: String {
        reading.pressure.formatted(.measurement(width: .abbreviated, usage: .barometric))
    }

    private var changeText: String? {
        guard let perHour = reading.changePerHour, abs(perHour) >= 0.1 else { return nil }
        return String(format: "%+.1f hPa/hr", perHour)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Pressure", systemImage: "barometer")
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(pressureText)
                            .font(.title.weight(.semibold))
                            .contentTransition(.numericText())
                        Label(reading.tendency.label, systemImage: reading.tendency.symbolName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(reading.tendency == .falling ? .green : .secondary)
                        if let changeText {
                            Text(changeText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(reading.tendency.fishingNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if samples.count > 1 {
                        PressureTrendChart(samples: samples, now: .now)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }
}

// MARK: - Solunar details

private struct SolunarDetailsCard: View {
    let conditions: FishingConditions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Sun & Moon", systemImage: "moon.stars")
            GlassCard {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        MoonArc(phase: conditions.moonPhase)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conditions.moonPhase.displayName)
                                .font(.headline)
                            Text("\(conditions.moonPhase.biteRating) solunar influence")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)

                    Divider()

                    HStack {
                        TimeFact(label: "Sunrise", date: conditions.sunrise, systemImage: "sunrise")
                        TimeFact(label: "Sunset", date: conditions.sunset, systemImage: "sunset")
                    }
                    HStack {
                        TimeFact(label: "Moonrise", date: conditions.moonrise, systemImage: "moonrise")
                        TimeFact(label: "Moonset", date: conditions.moonset, systemImage: "moonset")
                    }
                }
            }
        }
    }
}

private struct TimeFact: View {
    let label: String
    let date: Date?
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(date?.formatted(date: .omitted, time: .shortened) ?? "—")
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
