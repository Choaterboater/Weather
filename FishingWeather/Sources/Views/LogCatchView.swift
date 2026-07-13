import CoreLocation
import Foundation
import PhotosUI
import SwiftUI
import UIKit

struct LogCatchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatchLog.self) private var log
    @Environment(WeatherStore.self) private var weather
    @Environment(LocationManager.self) private var location
    @Environment(SpotStore.self) private var spots
    @Environment(TideService.self) private var tides

    @AppStorage("selectedSpecies") private var defaultSpecies: Species = .all

    @State private var species: Species = .bass
    @State private var bait = ""
    @State private var length = ""
    @State private var weight = ""
    @State private var notes = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var recognizer = FishRecognizer()

    var body: some View {
        NavigationStack {
            Form {
                Section("Catch") {
                    Picker("Species", selection: $species) {
                        ForEach(Species.allCases.filter { $0 != .all }) { species in
                            Text(species.displayName).tag(species)
                        }
                    }
                    TextField("Bait / lure", text: $bait)
                    TextField("Length (in)", text: $length)
                        .keyboardType(.decimalPad)
                    TextField("Weight (lb)", text: $weight)
                        .keyboardType(.decimalPad)
                }

                Section("Photo") {
                    let hasPhoto = photo != nil
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .clipShape(.rect(cornerRadius: 12))
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(hasPhoto ? "Change Photo" : "Add Photo", systemImage: "photo")
                    }
                    if hasPhoto {
                        identifyControl
                    }
                }

                Section("Notes") {
                    TextField("Anything worth remembering", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let snapshot = conditionsSnapshot {
                    Section("Conditions (auto)") {
                        ForEach(snapshot, id: \.label) { item in
                            LabeledContent(item.label, value: item.value)
                        }
                    }
                }
            }
            .navigationTitle("Log Catch")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.smooth, value: recognizer.status)
            .sensoryFeedback(trigger: recognizer.status) { _, newValue in
                if case .ready = newValue { return .success }
                if case .failed = newValue { return .error }
                return nil
            }
            .sensoryFeedback(.selection, trigger: species)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(bait.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if defaultSpecies != .all { species = defaultSpecies }
            }
            .task(id: pickerItem) {
                guard let selectedItem = pickerItem,
                      let data = try? await selectedItem.loadTransferable(type: Data.self),
                      !Task.isCancelled,
                      pickerItem == selectedItem,
                      let image = UIImage(data: data)
                else { return }
                photo = image
                recognizer.reset()
            }
        }
    }

    // MARK: - Fish recognition

    @ViewBuilder
    private var identifyControl: some View {
        switch recognizer.status {
        case .idle, .ready, .failed:
            Button {
                identify()
            } label: {
                Label("Identify species", systemImage: "sparkles")
                    .symbolEffect(.bounce, value: recognizer.status == .ready)
            }
            if case .ready = recognizer.status, let result = recognizer.result {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Looks like \(result.commonName)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    if result.matchedSpecies != nil {
                        Text("Set species to \(result.matchedSpecies!.displayName).")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    } else if !result.note.isEmpty {
                        Text(result.note)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    }
                }
            }
            if case .failed(let message) = recognizer.status {
                Text(message)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.chartDim)
            }
        case .working:
            HStack(spacing: 8) {
                ProgressView()
                Text("Identifying…")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.chartDim)
            }
        case .unavailable(let message):
            Text(message)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Ink.chartDim)
        }
    }

    private func identify() {
        guard let photo else { return }
        Task {
            await recognizer.identify(image: photo)
            if let matched = recognizer.result?.matchedSpecies {
                species = matched
            }
        }
    }

    // MARK: - Conditions snapshot

    private var activeCLLocation: CLLocation? {
        spots.selectedSpot?.location ?? location.location
    }

    /// Only snapshot weather that belongs to the active location.
    private var weatherSnapshot: WeatherSnapshot? {
        guard let activeCLLocation,
              weather.hasData(for: activeCLLocation)
        else { return nil }
        return weather.snapshot
    }

    private var conditions: FishingConditions? {
        weatherSnapshot.map { FishingConditions.make(snapshot: $0) }
    }

    private var activeLocation: (latitude: Double, longitude: Double)? {
        guard let activeCLLocation else { return nil }
        return (activeCLLocation.coordinate.latitude, activeCLLocation.coordinate.longitude)
    }

    private var airTempF: Double? {
        guard let celsius = weatherSnapshot?.current.temperatureCelsius else { return nil }
        return Measurement(value: celsius, unit: UnitTemperature.celsius)
            .converted(to: .fahrenheit)
            .value
    }

    private var dewPointF: Double? {
        guard let celsius = weatherSnapshot?.current.dewPointCelsius else { return nil }
        return Measurement(value: celsius, unit: UnitTemperature.celsius)
            .converted(to: .fahrenheit)
            .value
    }

    /// Tide movement now — "Rising", "Falling", or "Slack" — but only at a
    /// coastal spot whose tide data is already loaded (no fetch is forced when
    /// opening the form). Nil inland or when tides haven't been viewed.
    private var tidePhase: String? {
        guard let activeCLLocation else { return nil }
        return Self.tidePhase(
            events: tides.allEvents,
            hasMatchingData: tides.hasData(for: activeCLLocation),
            now: .now
        )
    }

    nonisolated static func tidePhase(
        events: [TideEvent],
        hasMatchingData: Bool,
        now: Date
    ) -> String? {
        guard hasMatchingData,
              let next = events.first(where: { $0.time > now }),
              let prev = events.last(where: { $0.time <= now })
        else { return nil }
        let slackWindow: TimeInterval = 45 * 60
        if next.time.timeIntervalSince(now) < slackWindow
            || now.timeIntervalSince(prev.time) < slackWindow {
            return "Slack"
        }
        return next.kind == .high ? "Rising" : "Falling"
    }

    private var conditionsSnapshot: [(label: String, value: String)]? {
        guard let conditions, let weatherSnapshot else { return nil }
        var items: [(String, String)] = []
        items.append((
            "Pressure",
            conditions.pressure.pressure == nil
                ? "Unavailable"
                : conditions.pressure.tendency.label
        ))
        items.append(("Moon", conditions.moonPhase.displayName))
        items.append((
            "Air temp",
            WeatherUnits.wholeTemperature(
                celsius: weatherSnapshot.current.temperatureCelsius
            )
        ))
        items.append((
            "Dew Point",
            weatherSnapshot.current.dewPointCelsius.map {
                WeatherUnits.wholeTemperature(celsius: $0)
            } ?? "Unavailable"
        ))
        let spotName = spots.selectedSpot?.name ?? location.descriptor.displayName
        items.append(("Where", spotName))
        return items
    }

    /// `Double.init(String)` is locale-independent: it returns nil for "3,5",
    /// which is the only thing a decimal pad produces in comma-decimal locales —
    /// silently dropping the angler's measurements.
    private func parseMeasurement(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed) ?? Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private func save() {
        let entry = CatchEntry(
            species: species,
            bait: bait.trimmingCharacters(in: .whitespacesAndNewlines),
            lengthInches: parseMeasurement(length),
            weightPounds: parseMeasurement(weight),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: activeLocation?.latitude,
            longitude: activeLocation?.longitude,
            spotName: spots.selectedSpot?.name ?? location.descriptor.displayName,
            pressureTendency: conditions.flatMap {
                $0.pressure.pressure == nil ? nil : $0.pressure.tendency.label
            },
            moonPhase: conditions?.moonPhase.displayName,
            airTempF: airTempF,
            dewPointF: dewPointF,
            windMph: conditions.map {
                WeatherUnits.milesPerHour(
                    metersPerSecond: $0.wind.speedMetersPerSecond
                )
            },
            tidePhase: tidePhase
        )
        log.add(entry, photo: photo)
        dismiss()
    }
}
