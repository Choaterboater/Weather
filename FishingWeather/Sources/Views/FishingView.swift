import SwiftUI
import WeatherKit

struct FishingView: View {
    @Environment(WeatherStore.self) private var weather
    @AppStorage("selectedSpecies") private var species: Species = .all

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SpeciesPicker(selection: $species)
                    .padding(.top, 4)
                SpeciesFocusCard(species: species)

                if let conditions = makeConditions() {
                    BiteWindowsCard(conditions: conditions)
                    PressureCard(reading: conditions.pressure)
                    SolunarDetailsCard(conditions: conditions)
                } else if weather.isLoading {
                    ProgressView("Reading conditions…")
                        .padding(.top, 80)
                } else {
                    ContentUnavailableView(
                        "No conditions yet",
                        systemImage: "fish",
                        description: Text("Weather data is needed to compute fishing windows.")
                    )
                    .padding(.top, 80)
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
    }

    private func makeConditions() -> FishingConditions? {
        guard let current = weather.current,
              let hourly = weather.hourly,
              let today = weather.daily?.forecast.first else { return nil }
        return FishingConditions.make(current: current, hourly: hourly, today: today)
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
                        ForEach(conditions.windows) { window in
                            BiteWindowRow(window: window)
                        }
                    }
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
                        Image(systemName: conditions.moonPhase.symbolName)
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conditions.moonPhase.displayName)
                                .font(.headline)
                            Text("\(conditions.moonPhase.biteRating) solunar influence")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

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
