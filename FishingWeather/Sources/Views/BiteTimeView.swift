import CoreLocation
import Foundation
import SwiftUI

enum BiteTimeForecastPresentation: String, CaseIterable, Identifiable, Sendable {
    case timeline
    case proForecast

    var id: String { rawValue }
    var title: String { self == .timeline ? "Timeline" : "Pro Forecast" }
    var symbolName: String { self == .timeline ? "chart.xyaxis.line" : "tablecells" }
}

/// Pure selection ownership for BiteTime. Programmatic reconciliation never
/// advances the feedback identity; only a changed, snapped user choice does.
struct BiteTimeSelectionState: Equatable, Sendable {
    private(set) var selectedDate: Date?
    private(set) var feedbackGeneration = 0

    mutating func reset(around preferredDate: Date, in dates: [Date]) {
        selectedDate = Self.nearest(to: preferredDate, in: dates)
    }

    mutating func reconcile(with dates: [Date], around preferredDate: Date) {
        guard let selectedDate, dates.contains(selectedDate) else {
            reset(around: preferredDate, in: dates)
            return
        }
    }

    mutating func selectByUser(_ proposedDate: Date?, in dates: [Date]) {
        guard let proposedDate,
              let snapped = Self.nearest(to: proposedDate, in: dates),
              snapped != selectedDate else { return }
        selectedDate = snapped
        feedbackGeneration += 1
    }

    private static func nearest(to date: Date, in dates: [Date]) -> Date? {
        dates
            .filter { $0.timeIntervalSinceReferenceDate.isFinite }
            .min { lhs, rhs in
                let lhsDistance = abs(lhs.timeIntervalSince(date))
                let rhsDistance = abs(rhs.timeIntervalSince(date))
                if lhsDistance == rhsDistance { return lhs < rhs }
                return lhsDistance < rhsDistance
            }
    }
}

struct BiteTimeSourcePresentation: Equatable, Sendable {
    let title: String
    let freshness: String
    let detail: String?
    let symbolName: String

    static func make(
        provenance: WeatherProvenance,
        now: Date,
        timeZone: TimeZone,
        locale: Locale
    ) -> Self {
        let title: String
        let symbolName: String
        switch provenance.source {
        case .weatherKit:
            title = provenance.isFallback ? "Apple Weather fallback" : "Apple Weather"
            symbolName = "apple.logo"
        case .nws:
            title = provenance.isFallback
                ? "National Weather Service fallback"
                : "National Weather Service"
            symbolName = "building.columns"
        case .cache:
            title = "Cached forecast"
            symbolName = "internaldrive"
        }

        let age = max(0, now.timeIntervalSince(provenance.fetchedAt))
        let prefix = provenance.source == .cache ? "Cached" : "Updated"
        let freshness: String
        if age < 60 {
            freshness = "\(prefix) just now"
        } else if age < 3_600 {
            freshness = "\(prefix) \(Int(age / 60)) min ago"
        } else if age < 24 * 3_600 {
            freshness = "\(prefix) \(Int(age / 3_600)) hr ago"
        } else {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            freshness = "\(prefix) \(formatter.string(from: provenance.fetchedAt))"
        }

        let detail: String? = provenance.source == .cache
            ? provenance.attribution
            : nil
        return Self(
            title: title,
            freshness: freshness,
            detail: detail,
            symbolName: symbolName
        )
    }
}

/// Determines whether the selected provider hour can truthfully be described
/// as current. A cached point must be both in the captured clock hour and
/// recently fetched; an old cache may still be useful, but it is never "now."
enum BiteTimeCurrentDecision {
    static let maximumCurrentCacheAge: TimeInterval = 15 * 60

    static func isCurrent(
        pointDate: Date,
        capturedNow: Date,
        provenance: WeatherProvenance,
        calendar: Calendar
    ) -> Bool {
        guard calendar.isDate(
            pointDate,
            equalTo: capturedNow,
            toGranularity: .hour
        ) else { return false }

        guard provenance.source == .cache else { return true }
        let age = capturedNow.timeIntervalSince(provenance.fetchedAt)
        return age >= 0 && age <= maximumCurrentCacheAge
    }
}

struct BiteTimeLocationAccessibility: Equatable, Sendable {
    let label: String
    let value: String?

    static func make(title: String, subtitle: String?) -> Self {
        Self(
            label: "Fishing location, \(title)",
            value: subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty
        )
    }
}

struct BiteTimeErrorPresentation: Equatable, Sendable {
    let title: String
    let message: String
    let symbolName: String

    static func make(for error: WeatherProviderError) -> Self {
        switch error.presentationKind {
        case .authentication:
            Self(
                title: "Weather authorization unavailable",
                message: "Apple Weather could not authenticate, and no fallback forecast was available.",
                symbolName: "lock.trianglebadge.exclamationmark"
            )
        case .network:
            Self(
                title: "You're offline",
                message: "Reconnect to update the forecast. Saved fishing tools still work.",
                symbolName: "wifi.slash"
            )
        case .rateLimited(let retryAfter):
            Self(
                title: "Weather service is busy",
                message: retryAfter.map {
                    "Try again in about \(Int($0.rounded())) seconds."
                } ?? "Wait a moment, then try the forecast again.",
                symbolName: "clock.badge.exclamationmark"
            )
        case .serviceUnavailable:
            Self(
                title: "Forecast temporarily unavailable",
                message: "The weather providers are having an outage. Try again shortly.",
                symbolName: "cloud.bolt"
            )
        case .unsupportedRegion:
            Self(
                title: "Forecast unavailable here",
                message: "The active weather providers do not cover this location.",
                symbolName: "map"
            )
        case .decoding:
            Self(
                title: "Forecast couldn't be read",
                message: "The provider returned an unexpected response. Try again for a fresh copy.",
                symbolName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
            )
        }
    }
}

/// Optional deterministic tide values used by the permanent debug preview.
/// Production leaves this nil and consumes the committed TideService state.
struct BiteTimeTideSnapshot {
    let events: [TideEvent]
    let allEvents: [TideEvent]
    let samples: [TideSample]
    let stationName: String?
    let distanceMiles: Double?
    var isLoading = false
    var lastError: String?
}

/// One decision-first composition over the neutral weather snapshot. This is
/// the sole owner of species, selected forecast hour, bait context, selection
/// feedback, tide display loading, and pull-to-refresh for the BiteTime tab.
struct BiteTimeView: View {
    @Environment(WeatherStore.self) private var weather
    @Environment(SpotStore.self) private var spots
    @Environment(LocationManager.self) private var location
    @Environment(TideService.self) private var tides
    @Environment(CatchLog.self) private var catchLog
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @AppStorage private var species: Species
    @State private var engine: BaitEngine
    @State private var selection = BiteTimeSelectionState()
    @State private var presentation = BiteTimeForecastPresentation.timeline
    @State private var speciesFeedbackGeneration = 0
    @State private var capturedNow: Date

    private let fixedNow: Date?
    private let allowsAutomaticTideLoad: Bool
    private let tideOverride: BiteTimeTideSnapshot?
    private let preferencesStore: UserDefaults?

    init(
        fixedNow: Date? = nil,
        allowsAutomaticTideLoad: Bool = true,
        tideOverride: BiteTimeTideSnapshot? = nil,
        preferencesStore: UserDefaults? = nil,
        initialSpecies: Species = .all,
        engine: BaitEngine? = nil
    ) {
        self.fixedNow = fixedNow
        self.allowsAutomaticTideLoad = allowsAutomaticTideLoad
        self.tideOverride = tideOverride
        self.preferencesStore = preferencesStore
        _capturedNow = State(initialValue: fixedNow ?? .now)
        _species = AppStorage(
            wrappedValue: initialSpecies,
            "selectedSpecies",
            store: preferencesStore
        )
        _engine = State(initialValue: engine ?? BaitEngine())
    }

    private var now: Date { capturedNow }

    private var activeLocation: CLLocation? {
        spots.selectedSpot?.location ?? location.location
    }

    private var activeLocationKey: String {
        guard let coordinate = activeLocation?.coordinate else { return "none" }
        let latitude = (coordinate.latitude * 100).rounded() / 100
        let longitude = (coordinate.longitude * 100).rounded() / 100
        return "\(latitude),\(longitude)"
    }

    private var matchingSnapshot: WeatherSnapshot? {
        guard let activeLocation,
              weather.hasData(for: activeLocation) else { return nil }
        return weather.snapshot
    }

    private var forecastTimeZone: TimeZone {
        matchingSnapshot
            .flatMap { TimeZone(identifier: $0.timeZoneIdentifier) }
            ?? .current
    }

    private var tideState: BiteTimeTideSnapshot {
        if let tideOverride { return tideOverride }
        return BiteTimeTideSnapshot(
            events: tides.events,
            allEvents: tides.allEvents,
            samples: tides.samples,
            stationName: tides.station?.name,
            distanceMiles: tides.distanceMiles,
            isLoading: tides.isLoading,
            lastError: tides.lastError
        )
    }

    private var hasCommittedTides: Bool {
        if tideOverride != nil { return true }
        guard let activeLocation, matchingSnapshot != nil else { return false }
        return tides.hasData(for: activeLocation, on: now)
    }

    private var committedTideSamples: [TideSample] {
        hasCommittedTides ? tideState.samples : []
    }

    private var personalWeights: FactorWeights {
        PersonalScoreModel.weights(from: catchLog.entries, species: species)
    }

    private var forecastPoints: [ForecastPoint] {
        guard let snapshot = matchingSnapshot else { return [] }
        let forecastStart = forecastCalendar.dateInterval(
            of: .hour,
            for: now
        )?.start ?? now
        return ForecastSeriesBuilder.build(
            weather: snapshot,
            tideSamples: committedTideSamples,
            species: species,
            weights: personalWeights,
            now: forecastStart
        )
    }

    private var preferredForecastDate: Date {
        forecastPoints.first {
            forecastCalendar.isDate(
                $0.date,
                equalTo: now,
                toGranularity: .hour
            )
        }?.date ?? now
    }

    private var selectedPoint: ForecastPoint? {
        let preferred = selection.selectedDate
            ?? preferredForecastDate
        return ForecastSelection.nearest(to: preferred, in: forecastPoints)
    }

    private var forecastSelection: Binding<Date?> {
        Binding {
            selection.selectedDate ?? selectedPoint?.date
        } set: { proposed in
            selection.selectByUser(proposed, in: forecastPoints.map(\.date))
        }
    }

    private var speciesSelection: Binding<Species> {
        Binding {
            species
        } set: { newValue in
            guard newValue != species else { return }
            species = newValue
            speciesFeedbackGeneration += 1
        }
    }

    private var conditions: FishingConditions? {
        guard let snapshot = matchingSnapshot,
              let selectedPoint else { return nil }
        return FishingConditions.make(
            snapshot: snapshot,
            forecastPoint: selectedPoint,
            calendar: forecastCalendar
        )
    }

    private var bestBaitContext: BestBaitContext? {
        guard let activeLocation,
              let snapshot = matchingSnapshot,
              let selectedPoint else { return nil }
        return BestBaitContext(
            species: species,
            coordinate: activeLocation.coordinate,
            weatherFetchedAt: snapshot.provenance.fetchedAt,
            tideFingerprint: BaitContextKey.tideFingerprint(
                events: hasCommittedTides ? tideState.allEvents : [],
                samples: committedTideSamples
            ),
            forecastPoint: selectedPoint
        )
    }

    private var selectedWindow: BiteWindow? {
        guard let selectedPoint else { return nil }
        if let active = selectedPoint.solunarWindow { return active }
        return forecastPoints
            .compactMap(\.solunarWindow)
            .filter { $0.peak > selectedPoint.date }
            .min { $0.peak < $1.peak }
    }

    private var showsTides: Bool {
        if tideOverride != nil { return true }
        if let waterType = spots.selectedSpot?.waterType {
            return waterType != .freshwater
        }
        return tideState.isLoading
            || tideState.stationName != nil
            || tideState.lastError != nil
    }

    private var descriptorTitle: String {
        spots.selectedSpot?.name ?? location.descriptor.displayName
    }

    private var descriptorSubtitle: String? {
        if let spot = spots.selectedSpot {
            let parts = [spot.kind?.displayName, spot.stateCode]
                .compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        return location.descriptor.subtitle
    }

    private var forecastCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = forecastTimeZone
        return calendar
    }

    private var forecastRevision: String {
        guard let snapshot = matchingSnapshot else {
            return "\(activeLocationKey)|none"
        }
        return "\(activeLocationKey)|\(snapshot.provenance.fetchedAt.timeIntervalSince1970)"
    }

    private var tideTaskKey: String {
        let date = now
        return "\(activeLocationKey)|\(Int(date.timeIntervalSince1970 / 86_400))"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                locationHeader

                if let snapshot = matchingSnapshot {
                    loadedContent(snapshot)
                } else {
                    unavailableContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 112)
        }
        .background(
            WeatherTheme.skyBackdrop(
                conditionText: matchingSnapshot?.current.conditionText,
                symbolName: matchingSnapshot?.current.symbolName
            )
        )
        .refreshable { await refresh() }
        .task(id: tideTaskKey) {
            guard allowsAutomaticTideLoad,
                  let activeLocation else { return }
            await tides.load(
                near: activeLocation,
                on: now
            )
        }
        .onAppear(perform: reconcileSelection)
        .onChange(of: forecastRevision) {
            let preferred = preferredForecastDate
            selection.reset(around: preferred, in: forecastPoints.map(\.date))
        }
        .onChange(of: forecastPoints.map(\.date)) {
            reconcileSelection()
        }
        .sensoryFeedback(.selection, trigger: selection.feedbackGeneration)
        .sensoryFeedback(.selection, trigger: speciesFeedbackGeneration)
    }

    @ViewBuilder
    private func loadedContent(_ snapshot: WeatherSnapshot) -> some View {
        let capturedNow = now

        if !snapshot.alerts.isEmpty {
            WeatherAlertsView(alerts: snapshot.alerts)
        }

        if let selectedPoint {
            BiteTimeHero(
                point: selectedPoint,
                species: species,
                timeZone: forecastTimeZone,
                isCurrentHour: BiteTimeCurrentDecision.isCurrent(
                    pointDate: selectedPoint.date,
                    capturedNow: capturedNow,
                    provenance: snapshot.provenance,
                    calendar: forecastCalendar
                ),
                window: selectedWindow
            )
        }

        BestBaitTodayView(
            context: bestBaitContext,
            species: species,
            engine: engine
        )

        sourceStatus(snapshot.provenance)

        if let error = weather.lastProviderError {
            refreshFailure(error)
        }

        forecastPresentation
        selectedSpeciesSection
        otherSpeciesSection

        if !snapshot.daily.isEmpty {
            DailyForecastView(
                daily: snapshot.daily,
                timeZoneIdentifier: snapshot.timeZoneIdentifier,
                now: capturedNow
            )
        }

        waterSection
        planTheWeek
        deepDetailLinks
    }

    private var locationHeader: some View {
        let accessibility = BiteTimeLocationAccessibility.make(
            title: descriptorTitle,
            subtitle: descriptorSubtitle
        )
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: spots.selectedSpot == nil ? "location.fill" : "mappin.and.ellipse")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(Ink.brass)
                .frame(width: 28, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptorTitle)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Ink.chart)
                    .fixedSize(horizontal: false, vertical: true)
                if let descriptorSubtitle {
                    Text(descriptorSubtitle)
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .foregroundStyle(Ink.chartDim)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility.label)
        .accessibilityValue(accessibility.value ?? "")
        .accessibilityIdentifier("bitetime.location")
    }

    @ViewBuilder
    private func sourceStatus(_ provenance: WeatherProvenance) -> some View {
        if let fixedNow {
            sourceStatusContent(provenance, at: fixedNow)
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                sourceStatusContent(provenance, at: context.date)
            }
        }
    }

    private func sourceStatusContent(
        _ provenance: WeatherProvenance,
        at referenceDate: Date
    ) -> some View {
        let source = BiteTimeSourcePresentation.make(
            provenance: provenance,
            now: referenceDate,
            timeZone: forecastTimeZone,
            locale: .current
        )
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: source.symbolName)
                .foregroundStyle(provenance.source == .cache ? Ink.brass : Ink.tide)
                .frame(width: 22)
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
            Spacer(minLength: 0)
            if weather.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(source.title)
        .accessibilityValue(
            ([weather.isLoading ? "Updating" : source.freshness, source.detail]
                .compactMap { $0 })
                .joined(separator: ", ")
        )
        .accessibilityIdentifier("bitetime.source")
    }

    private func refreshFailure(_ error: WeatherProviderError) -> some View {
        let presentation = BiteTimeErrorPresentation.make(for: error)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: presentation.symbolName)
                .foregroundStyle(Ink.brass)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text("Update failed — showing saved forecast")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.chart)
                Text(presentation.message)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(Ink.chartDim)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.brass.opacity(0.12), in: .rect(cornerRadius: 16))
        .accessibilityIdentifier("bitetime.refreshFailure")
    }

    private var forecastPresentation: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Forecast detail")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Ink.chart)
                Text("One selected hour across every view")
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .foregroundStyle(Ink.chartDim)
            }

            HStack(spacing: 8) {
                ForEach(BiteTimeForecastPresentation.allCases) { option in
                    Button {
                        presentation = option
                    } label: {
                        Label(option.title, systemImage: option.symbolName)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(presentation == option ? Ink.abyss : Ink.chartDim)
                    .background(
                        presentation == option ? Ink.brass : Ink.hull,
                        in: .capsule
                    )
                    .overlay {
                        Capsule().stroke(
                            presentation == option ? Ink.brass : Ink.hullLine,
                            lineWidth: 1
                        )
                    }
                    .accessibilityAddTraits(presentation == option ? .isSelected : [])
                    .accessibilityIdentifier(
                        option == .timeline ? "bitetime.timeline" : "bitetime.proForecast"
                    )
                }
            }

            Group {
                switch presentation {
                case .timeline:
                    HourlyForecastView(
                        points: forecastPoints,
                        selectedDate: forecastSelection,
                        timeZone: forecastTimeZone
                    )
                case .proForecast:
                    ProForecastMatrix(
                        points: forecastPoints,
                        selectedDate: forecastSelection,
                        timeZone: forecastTimeZone,
                        now: now,
                        preferencesStore: preferencesStore
                    )
                }
            }
            .accessibilityIdentifier("bitetime.forecastContent")
        }
    }

    private var selectedSpeciesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fish this hour")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Ink.chart)
                Text("Choose a species for tailored scoring and bait advice.")
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .foregroundStyle(Ink.chartDim)
            }

            SpeciesPicker(
                selection: speciesSelection,
                waterType: spots.selectedSpot?.waterType
            )

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "fish.fill")
                    .font(.title2)
                    .foregroundStyle(species.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(species == .all ? "All species" : species.displayName)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Ink.chart)
                    Text(species.focusNote)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Ink.chartDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Ink.card.opacity(0.82), in: .rect(cornerRadius: 20))
        }
        .accessibilityIdentifier("bitetime.selectedSpecies")
    }

    private var relevantOtherSpecies: [Species] {
        Species.allCases.filter {
            $0 != .all
                && $0 != species
                && $0.isAvailable(for: spots.selectedSpot?.waterType)
        }
    }

    private var otherSpeciesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Other species")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Ink.chart)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(relevantOtherSpecies) { option in
                        otherSpeciesButton(option)
                    }
                }
            }
        }
        .accessibilityIdentifier("bitetime.otherSpecies")
    }

    private func otherSpeciesButton(_ option: Species) -> some View {
        let score = selectedScore(for: option)
        let band = score.flatMap(BiteScoreBand.band(for:))
        let scoreText = score.map(String.init) ?? "—"
        let accessibilityValue = score.map {
            "Bite score \($0), \(BiteScoreBand.band(for: $0)?.title ?? "unavailable")"
        } ?? "Bite score unavailable"

        return Button {
            speciesSelection.wrappedValue = option
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "fish.fill")
                        .foregroundStyle(option.tint)
                    Text(option.displayName)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Ink.chart)
                        .lineLimit(2)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(scoreText)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(band?.color ?? Ink.chartDim)
                    Text(band?.title ?? "Unavailable")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Ink.chartDim)
                }
            }
            .padding(14)
            .frame(width: 154, alignment: .leading)
            .frame(minHeight: 104, alignment: .leading)
            .background(Ink.card.opacity(0.9), in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Ink.hullLine, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName)
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var waterSection: some View {
        if showsTides {
            TideCard(
                events: tideState.events,
                samples: tideState.samples,
                stationName: tideState.stationName,
                distanceMiles: tideState.distanceMiles,
                isLoading: tideState.isLoading,
                lastError: tideState.lastError,
                referenceDate: selectedPoint?.date ?? now
            )
            .environment(\.timeZone, forecastTimeZone)
        } else if let activeLocation {
            WaterConditionsCard(location: activeLocation)
        }
    }

    @ViewBuilder
    private var planTheWeek: some View {
        if let activeLocation {
            NavigationLink {
                TripPlannerScreen(
                    location: activeLocation,
                    species: species,
                    locationName: descriptorTitle
                )
            } label: {
                planLabel
                    .padding(17)
                    .background(Ink.card.opacity(0.9), in: .rect(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Ink.hullLine, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bitetime.planWeek")
        }
    }

    @ViewBuilder
    private var planLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title2)
                        .foregroundStyle(Ink.brass)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Ink.chartDim)
                }
                planCopy
            }
        } else {
            HStack(spacing: 14) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(Ink.brass)
                    .frame(width: 34)
                planCopy
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Ink.chartDim)
            }
        }
    }

    private var planCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Plan the Week")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Ink.chart)
            Text("Rank the best fishing windows ahead")
                .font(.system(.callout, design: .rounded, weight: .medium))
                .foregroundStyle(Ink.chartDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var deepDetailLinks: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                weatherDetailLink
                fishingDetailLink
            }
        } else {
            HStack(spacing: 10) {
                weatherDetailLink
                fishingDetailLink
            }
        }
    }

    private var weatherDetailLink: some View {
        NavigationLink {
            WeatherDashboardView(fixedNow: fixedNow)
                .navigationTitle("Weather Details")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            detailLink("Weather", symbol: "cloud.sun")
        }
        .accessibilityIdentifier("bitetime.weatherDetails")
    }

    @ViewBuilder
    private var fishingDetailLink: some View {
        if let conditions, let selectedPoint {
            NavigationLink {
                FishingView(
                    species: species,
                    score: FishingScorer.score(
                        conditions: conditions,
                        species: species,
                        tideEvents: hasCommittedTides ? tideState.allEvents : [],
                        weights: personalWeights,
                        now: selectedPoint.date
                    ),
                    conditions: conditions,
                    tide: showsTides ? tideState : nil,
                    activeLocation: activeLocation,
                    hourlySamples: matchingSnapshot?.hourly.samples(
                        now: selectedPoint.date
                    ) ?? [],
                    referenceDate: selectedPoint.date,
                    forecastTimeZone: forecastTimeZone
                )
                .navigationTitle("Fishing Details")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                detailLink("Fishing", symbol: "fish")
            }
            .accessibilityIdentifier("bitetime.fishingDetails")
        }
    }

    private func detailLink(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(Ink.chart)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Ink.hull.opacity(0.72), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Ink.hullLine, lineWidth: 1)
            }
    }

    @ViewBuilder
    private var unavailableContent: some View {
        if activeLocation == nil {
            ContentUnavailableView(
                "Finding your location",
                systemImage: "location",
                description: Text("BiteTime will load as soon as a fishing location is available.")
            )
            .frame(maxWidth: .infinity, minHeight: 300)
        } else if weather.isLoading || weather.lastProviderError == nil {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Ink.brass)
                Text("Building your BiteTime forecast…")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.chart)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
        } else if let error = weather.lastProviderError {
            let presentation = BiteTimeErrorPresentation.make(for: error)
            ContentUnavailableView {
                Label(presentation.title, systemImage: presentation.symbolName)
            } description: {
                Text(presentation.message)
            } actions: {
                Button("Try Again") {
                    Task { await refresh() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, minHeight: 340)
            .accessibilityIdentifier("bitetime.error")
        }
    }

    private func selectedScore(for option: Species) -> Int? {
        guard let snapshot = matchingSnapshot, let selectedPoint else { return nil }
        let points = ForecastSeriesBuilder.build(
            weather: snapshot,
            tideSamples: committedTideSamples,
            species: option,
            weights: PersonalScoreModel.weights(
                from: catchLog.entries,
                species: option
            ),
            now: now
        )
        return ForecastSelection.nearest(to: selectedPoint.date, in: points)?.biteScore
    }

    private func reconcileSelection() {
        let preferred = preferredForecastDate
        selection.reconcile(
            with: forecastPoints.map(\.date),
            around: preferred
        )
    }

    private func refresh() async {
        location.refresh()
        guard let activeLocation else { return }
        await weather.load(for: activeLocation, force: true)
        guard allowsAutomaticTideLoad else { return }
        await tides.load(
            near: activeLocation,
            on: now,
            force: true
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
