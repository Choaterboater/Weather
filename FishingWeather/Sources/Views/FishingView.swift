import Foundation
import CoreLocation
import SwiftUI

/// One immutable forecast reference shared by every Fishing Details card.
/// Keeping the card-specific names makes accidental wall-clock regressions
/// visible in tests and at each call site.
struct FishingDetailReference: Equatable, Sendable {
    let referenceDate: Date
    let forecastTimeZone: TimeZone

    var biteWindowsDate: Date { referenceDate }
    var tideDate: Date { referenceDate }
    var pressureDate: Date { referenceDate }
}

struct FishingView: View {
    @Environment(CatchLog.self) private var catchLog

    let species: Species
    let score: FishingScore
    let conditions: FishingConditions
    let tide: BiteTimeTideSnapshot?
    let activeLocation: CLLocation?
    let hourlySamples: [HourSample]
    let referenceDate: Date
    let forecastTimeZone: TimeZone

    @State private var showsPatterns = false

    private var tunedCatchCount: Int {
        PersonalScoreModel.informingCatchCount(catchLog.entries, species: species)
    }
    private var learningCatchCount: Int {
        PersonalScoreModel.sampleCount(catchLog.entries, species: species)
    }
    private var detailReference: FishingDetailReference {
        FishingDetailReference(
            referenceDate: referenceDate,
            forecastTimeZone: forecastTimeZone
        )
    }

    var body: some View {
        ScrollView {
            GlassCardStack(spacing: 20) {
                SpeciesFocusCard(species: species)
                FishingScoreCard(
                    score: score,
                    tunedCount: tunedCatchCount,
                    learningCount: learningCatchCount,
                    learningThreshold: PersonalScoreModel.minCatches,
                    onTapTuned: { showsPatterns = true }
                )
                BiteWindowsCard(
                    conditions: conditions,
                    referenceDate: detailReference.biteWindowsDate
                )
                if let tide {
                    TideCard(
                        events: tide.events,
                        samples: tide.samples,
                        stationName: tide.stationName,
                        distanceMiles: tide.distanceMiles,
                        isLoading: tide.isLoading,
                        lastError: tide.lastError,
                        referenceDate: detailReference.tideDate
                    )
                    .environment(\.timeZone, detailReference.forecastTimeZone)
                } else if let activeLocation {
                    WaterConditionsCard(location: activeLocation)
                }
                PressureCard(
                    reading: conditions.pressure,
                    samples: hourlySamples,
                    referenceDate: detailReference.pressureDate
                )
                SolunarDetailsCard(conditions: conditions)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Ink.backdrop)
        .environment(\.timeZone, detailReference.forecastTimeZone)
        .sheet(isPresented: $showsPatterns) {
            YourPatternsView(
                insights: PersonalInsightsBuilder.build(from: catchLog.entries, species: species),
                species: species
            )
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
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Ink.chart)
                    Text(species.focusNote)
                        .font(.system(.body, design: .rounded))
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
    let referenceDate: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reminderState: ReminderState = .none

    private enum ReminderState { case none, scheduled, tooLate }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Bite Windows", systemImage: "timer")
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    headline(at: referenceDate)
                    if conditions.windows.isEmpty {
                        Text("No solunar windows for this forecast day (moonrise/moonset unavailable).")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Ink.chartDim)
                    } else {
                        BiteWindowsTimeline(
                            windows: conditions.windows,
                            now: referenceDate
                        )
                        ForEach(conditions.windows) { window in
                            BiteWindowRow(window: window, now: referenceDate)
                        }
                        reminderControl(at: referenceDate)
                    }
                }
            }
        }
        // The card outlives its windows (weather refresh, spot switch): a
        // "Reminder set" badge must not survive for a window it never covered.
        .onChange(of: conditions.nextWindow(after: referenceDate)?.start) {
            reminderState = .none
        }
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
                            .font(.system(.callout, design: .rounded, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                case .scheduled:
                    Label("Reminder set", systemImage: "bell.fill")
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(Ink.bite)
                        .symbolEffect(
                            .bounce,
                            value: !reduceMotion && reminderState == .scheduled
                        )
                        .transition(
                            reduceMotion
                                ? .identity
                                : .scale.combined(with: .opacity)
                        )
                case .tooLate:
                    Label("That window is too soon to remind", systemImage: "bell.slash")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Ink.chartDim)
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: reminderState)
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
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Ink.chart)
            } icon: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Ink.bite)
                    .symbolEffect(
                        .variableColor.iterative,
                        options: .repeating,
                        isActive: !reduceMotion
                    )
            }
        } else if let next = conditions.nextWindow(after: date) {
            Label {
                Text("Next: \(next.period.rawValue) at \(next.peak.formatted(date: .omitted, time: .shortened))")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Ink.chart)
            } icon: {
                Image(systemName: "clock.badge")
                    .foregroundStyle(Ink.brass)
            }
        } else {
            Text("Today's feeding windows")
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .foregroundStyle(Ink.chart)
        }
    }
}

private struct BiteWindowRow: View {
    let window: BiteWindow
    let now: Date

    private var isActive: Bool { window.isActive(at: now) }

    private var timeRange: String {
        let start = window.start.formatted(date: .omitted, time: .shortened)
        let end = window.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(window.period.rawValue)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(window.period == .major ? Ink.bite : Ink.brass)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(window.period == .major ? Ink.bite.opacity(0.25) : Ink.brass.opacity(0.2))
                .clipShape(.capsule)

            VStack(alignment: .leading, spacing: 2) {
                Text(timeRange)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Ink.chart)
                Text(window.cause)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(Ink.chartDim)
            }

            Spacer()

            if isActive {
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Ink.bite)
            }
        }
    }
}

// MARK: - Pressure

private struct PressureCard: View {
    let reading: PressureReading
    var samples: [HourSample] = []
    let referenceDate: Date

    private var pressureText: String {
        reading.pressure?.formatted(
            .measurement(width: .abbreviated, usage: .barometric)
        ) ?? "Unavailable"
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
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Ink.chart)
                            .contentTransition(.numericText())
                        if reading.pressure != nil {
                            Label(reading.tendency.label, systemImage: reading.tendency.symbolName)
                                .font(.system(.callout, design: .rounded, weight: .semibold))
                                .foregroundStyle(reading.tendency == .falling ? Ink.bite : Ink.chartDim)
                            if let changeText {
                                Text(changeText)
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Ink.chartDim)
                            }
                        }
                    }
                    Text(
                        reading.pressure == nil
                            ? "Barometric pressure isn't available from this weather source."
                            : reading.tendency.fishingNote
                    )
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Ink.chartDim)
                    if samples.compactMap(\.pressureHPa).count > 1 {
                        PressureTrendChart(
                            samples: samples,
                            now: referenceDate
                        )
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
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(Ink.chart)
                            Text("\(conditions.moonPhase.biteRating) solunar influence")
                                .font(.system(.caption, design: .rounded, weight: .medium))
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
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.chartDim)
                    .textCase(.uppercase)
                    .tracking(1)
                Text(date?.formatted(date: .omitted, time: .shortened) ?? "—")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Ink.chart)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
