import Foundation
import CoreLocation
import SwiftUI
import WeatherKit

struct FishingView: View {
    @Environment(WeatherStore.self) private var weather
    @Environment(SpotStore.self) private var spots
    @Environment(LocationManager.self) private var location
    @Environment(TideService.self) private var tides
    @Environment(CatchLog.self) private var catchLog
    @AppStorage("selectedSpecies") private var species: Species = .all
    @State private var engine = BaitEngine()
    @State private var showsPatterns = false

    /// Weights tuned to the angler's catch history for the active species —
    /// standard weights until they've logged enough catches to learn from.
    private var personalWeights: FactorWeights {
        PersonalScoreModel.weights(from: catchLog.entries, species: species)
    }
    private var tunedCatchCount: Int {
        PersonalScoreModel.informingCatchCount(catchLog.entries, species: species)
    }
    private var learningCatchCount: Int {
        PersonalScoreModel.sampleCount(catchLog.entries, species: species)
    }

    /// True when the active spot is salt/brackish, or (no spot) we're loading /
    /// have / failed a coastal tide fetch — so the card isn't hidden mid-load.
    private var showsTides: Bool {
        if let waterType = spots.selectedSpot?.waterType {
            return waterType != .freshwater
        }
        return tides.isLoading || tides.station != nil || tides.lastError != nil
    }

    var body: some View {
        ScrollView {
            GlassCardStack(spacing: 20) {
                SpeciesPicker(selection: $species, waterType: spots.selectedSpot?.waterType)
                    .padding(.top, 4)

                if let loc = activeLocation {
                    planTheWeekLink(location: loc)
                }

                if let conditions = liveConditions {
                    // Re-evaluate score / active windows as the clock moves.
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        FishingScoreCard(
                            score: FishingScorer.score(
                                conditions: conditions,
                                species: species,
                                // allEvents spans yesterday–tomorrow so late-evening
                                // scoring sees the next event after midnight.
                                tideEvents: showsTides ? tides.allEvents : [],
                                weights: personalWeights,
                                now: context.date
                            ),
                            tunedCount: tunedCatchCount,
                            learningCount: learningCatchCount,
                            learningThreshold: PersonalScoreModel.minCatches,
                            onTapTuned: { showsPatterns = true }
                        )
                    }
                    SpeciesFocusCard(species: species)
                    BaitEngineView(
                        conditions: conditions,
                        species: species,
                        tideEvents: showsTides ? tides.allEvents : [],
                        engine: engine
                    )
                    BiteWindowsCard(conditions: conditions)
                    if showsTides {
                        TideCard(
                            events: tides.events,
                            samples: tides.samples,
                            stationName: tides.station?.name,
                            distanceMiles: tides.distanceMiles,
                            isLoading: tides.isLoading,
                            lastError: tides.lastError
                        )
                    } else if let loc = activeLocation {
                        WaterConditionsCard(location: loc)
                    }
                    PressureCard(reading: conditions.pressure, samples: hourlySamples)
                    SolunarDetailsCard(conditions: conditions)
                } else if weather.isLoading || (activeLocation != nil && weather.current == nil && weather.errorMessage == nil) {
                    ProgressView("Reading conditions…")
                        .padding(.top, 80)
                } else if weather.errorMessage != nil {
                    SpeciesFocusCard(species: species)
                    if let loc = activeLocation, let cachedPressure = WeatherSnapshots.cachedPressure(for: loc) {
                        CachedPressureCard(reading: cachedPressure, samples: hourlySamples)
                    }
                    ContentUnavailableView {
                        Label("Conditions unavailable", systemImage: "wifi.slash")
                    } description: {
                        Text("Couldn't reach the weather service. Pull to refresh, or retry once you're back online.")
                    } actions: {
                        Button("Retry") {
                            Task {
                                if let activeLocation {
                                    await weather.load(for: activeLocation, force: true)
                                }
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
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
        .background(Ink.backdrop)
        .sheet(isPresented: $showsPatterns) {
            YourPatternsView(
                insights: PersonalInsightsBuilder.build(from: catchLog.entries, species: species),
                species: species
            )
        }
        .task(id: activeLocationKey) {
            if let coordinate = activeLocation {
                await tides.load(near: coordinate)
            }
        }
        .onChange(of: species) { engine.reset() }
        .onChange(of: activeLocationKey) { engine.reset() }
        .sensoryFeedback(.selection, trigger: species)
    }

    private var activeLocation: CLLocation? {
        spots.selectedSpot?.location ?? location.location
    }

    private var planLocationName: String {
        spots.selectedSpot?.name ?? location.descriptor.displayName
    }

    /// Entry point to the Weekly Trip Planner.
    private func planTheWeekLink(location loc: CLLocation) -> some View {
        NavigationLink {
            TripPlannerScreen(location: loc, species: species, locationName: planLocationName)
        } label: {
            GlassCard {
                HStack(spacing: 14) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 24))
                        .foregroundStyle(Ink.brass)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plan the Week")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.chart)
                        Text("Best days & times to fish")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Only present weather that belongs to the active location.
    private var liveConditions: FishingConditions? {
        guard let activeLocation, weather.hasData(for: activeLocation) else { return nil }
        return weather.conditions
    }

    /// Re-keys the tide task whenever the active spot or GPS coordinate changes.
    private var activeLocationKey: String {
        guard let coord = activeLocation?.coordinate else { return "none" }
        return "\(coord.latitude.rounded(toPlaces: 2)),\(coord.longitude.rounded(toPlaces: 2))"
    }

    private var hourlySamples: [HourSample] {
        if let loc = activeLocation, weather.hasData(for: loc),
           let live = weather.hourly?.samples(), !live.isEmpty {
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
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(Ink.chart)
                        .contentTransition(.numericText())
                    Label(reading.tendency.label, systemImage: reading.tendency.symbolName)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(reading.tendency == .falling ? Ink.bite : Ink.chartDim)
                    if let perHour = reading.changePerHour, abs(perHour) >= 0.1 {
                        Text(String(format: "%+.1f hPa/hr", perHour))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    }
                }
                Text(reading.tendency.fishingNote)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.chartDim)
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
                    .font(.system(size: 20))
                    .foregroundStyle(species.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(species == .all ? "All species" : species.displayName)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Ink.chart)
                    Text(species.focusNote)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
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
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 14) {
                        headline(at: context.date)
                        if conditions.windows.isEmpty {
                            Text("No solunar windows for today (moonrise/moonset unavailable).")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(Ink.chartDim)
                        } else {
                            BiteWindowsTimeline(windows: conditions.windows, now: context.date)
                            ForEach(conditions.windows) { window in
                                BiteWindowRow(window: window, now: context.date)
                            }
                            reminderControl(at: context.date)
                        }
                    }
                }
            }
        }
        // The card outlives its windows (weather refresh, spot switch): a
        // "Reminder set" badge must not survive for a window it never covered.
        .onChange(of: conditions.nextWindow()?.start) { reminderState = .none }
    }

    @ViewBuilder
    private func reminderControl(at date: Date) -> some View {
        if let next = conditions.nextWindow(after: date) {
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
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                    }
                    .buttonStyle(.bordered)
                case .scheduled:
                    Label("Reminder set", systemImage: "bell.fill")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Ink.bite)
                        .symbolEffect(.bounce, value: reminderState == .scheduled)
                        .transition(.scale.combined(with: .opacity))
                case .tooLate:
                    Label("That window is too soon to remind", systemImage: "bell.slash")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
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
    private func headline(at date: Date) -> some View {
        if let active = conditions.activeWindow(at: date) {
            Label {
                Text("\(active.period.rawValue) window now — until \(active.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Ink.chart)
            } icon: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Ink.bite)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }
        } else if let next = conditions.nextWindow(after: date) {
            Label {
                Text("Next: \(next.period.rawValue) at \(next.peak.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Ink.chart)
            } icon: {
                Image(systemName: "clock.badge")
                    .foregroundStyle(Ink.brass)
            }
        } else {
            Text("Today's feeding windows")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Ink.chart)
        }
    }
}

private struct BiteWindowRow: View {
    let window: BiteWindow
    var now: Date = .now

    private var isActive: Bool { window.isActive(at: now) }

    private var timeRange: String {
        let start = window.start.formatted(date: .omitted, time: .shortened)
        let end = window.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(window.period.rawValue)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(window.period == .major ? Ink.bite : Ink.brass)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(window.period == .major ? Ink.bite.opacity(0.25) : Ink.brass.opacity(0.2))
                .clipShape(.capsule)

            VStack(alignment: .leading, spacing: 2) {
                Text(timeRange)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Ink.chart)
                Text(window.cause)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.chartDim)
            }

            Spacer()

            if isActive {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Ink.bite)
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
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.chart)
                            .contentTransition(.numericText())
                        Label(reading.tendency.label, systemImage: reading.tendency.symbolName)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(reading.tendency == .falling ? Ink.bite : Ink.chartDim)
                        if let changeText {
                            Text(changeText)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Ink.chartDim)
                        }
                    }
                    Text(reading.tendency.fishingNote)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
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
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundStyle(Ink.chart)
                            Text("\(conditions.moonPhase.biteRating) solunar influence")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Ink.chartDim)
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
                .foregroundStyle(Ink.chartDim)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Ink.chartDim)
                    .textCase(.uppercase)
                    .tracking(1)
                Text(date?.formatted(date: .omitted, time: .shortened) ?? "—")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Ink.chart)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
