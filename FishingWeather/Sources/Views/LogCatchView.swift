import PhotosUI
import SwiftUI
import UIKit
import WeatherKit

struct LogCatchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatchLog.self) private var log
    @Environment(WeatherStore.self) private var weather
    @Environment(LocationManager.self) private var location
    @Environment(SpotStore.self) private var spots

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
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .clipShape(.rect(cornerRadius: 12))
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(photo == nil ? "Add Photo" : "Change Photo", systemImage: "photo")
                    }
                    if photo != nil {
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
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        photo = image
                        recognizer.reset()
                    }
                }
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
                        .font(.subheadline.weight(.medium))
                    if result.matchedSpecies != nil {
                        Text("Set species to \(result.matchedSpecies!.displayName).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !result.note.isEmpty {
                        Text(result.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if case .failed(let message) = recognizer.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .working:
            HStack(spacing: 8) {
                ProgressView()
                Text("Identifying…").foregroundStyle(.secondary)
            }
        case .unavailable(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var conditions: FishingConditions? {
        guard let current = weather.current,
              let hourly = weather.hourly,
              let today = weather.daily?.forecast.first else { return nil }
        return FishingConditions.make(current: current, hourly: hourly, today: today)
    }

    private var activeLocation: (latitude: Double, longitude: Double)? {
        if let spot = spots.selectedSpot {
            return (spot.latitude, spot.longitude)
        }
        if let coordinate = location.location?.coordinate {
            return (coordinate.latitude, coordinate.longitude)
        }
        return nil
    }

    private var airTempF: Double? {
        weather.current?.temperature.converted(to: .fahrenheit).value
    }

    private var conditionsSnapshot: [(label: String, value: String)]? {
        guard let conditions else { return nil }
        var items: [(String, String)] = []
        items.append(("Pressure", conditions.pressure.tendency.label))
        items.append(("Moon", conditions.moonPhase.displayName))
        if let airTempF {
            items.append(("Air temp", "\(Int(airTempF.rounded()))°F"))
        }
        if let spotName = spots.selectedSpot?.name ?? location.placeName {
            items.append(("Where", spotName))
        }
        return items
    }

    private func save() {
        let entry = CatchEntry(
            species: species,
            bait: bait.trimmingCharacters(in: .whitespacesAndNewlines),
            lengthInches: Double(length),
            weightPounds: Double(weight),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: activeLocation?.latitude,
            longitude: activeLocation?.longitude,
            spotName: spots.selectedSpot?.name ?? location.placeName,
            pressureTendency: conditions?.pressure.tendency.label,
            moonPhase: conditions?.moonPhase.displayName,
            airTempF: airTempF
        )
        log.add(entry, photo: photo)
        dismiss()
    }
}
