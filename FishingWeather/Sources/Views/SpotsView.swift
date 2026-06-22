import CoreLocation
import MapKit
import SwiftUI

/// Spots tab. Glanceable, scrollable view of:
/// * the active location (GPS or saved spot)
/// * curated nearby spots (hand-picked, with full metadata)
/// * boat ramps & piers from OpenStreetMap (community-tagged, lighter rows)
/// * the user's own saved spots
struct SpotsView: View {
    @Environment(SpotStore.self) private var spots
    @Environment(LocationManager.self) private var location
    @Environment(CuratedSpotCatalog.self) private var catalog
    @Environment(OpenStreetMapClient.self) private var osm

    @State private var showsAddSheet = false

    private var here: CLLocation? {
        spots.selectedSpot?.location ?? location.location
    }

    private var curated: [FishingSpot] {
        guard let here else { return [] }
        return catalog.nearby(here)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                activeSection
                if !curated.isEmpty {
                    curatedSection
                }
                ospSection
                if !spots.spots.isEmpty {
                    savedSection
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [.teal.opacity(0.25), .cyan.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .disabled(location.location == nil)
            }
        }
        .sheet(isPresented: $showsAddSheet) {
            NavigationStack {
                AddSpotSheet { newSpot in
                    spots.add(newSpot)
                }
            }
        }
        .task(id: hereKey) {
            guard let here else { return }
            await osm.loadRamps(near: here)
        }
    }

    private var hereKey: String {
        guard let coord = here?.coordinate else { return "none" }
        return "\(coord.latitude.rounded()),\(coord.longitude.rounded())"
    }

    // MARK: - Sections

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Active", systemImage: "scope")
            VStack(spacing: 10) {
                Button {
                    spots.select(nil)
                } label: {
                    GlassCard {
                        HStack(spacing: 12) {
                            Image(systemName: "location.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.orange.opacity(0.15)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Current Location")
                                    .font(.headline)
                                if let placeName = location.placeName {
                                    Text(placeName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if spots.selectedSpotID == nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.headline)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                if let active = spots.selectedSpot {
                    NavigationLink {
                        SpotDetailView(spot: active)
                    } label: {
                        SpotCard(spot: active, distanceMiles: nil, isActive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var curatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Curated Nearby", systemImage: "star.fill")
            VStack(spacing: 10) {
                ForEach(curated) { spot in
                    NavigationLink {
                        SpotDetailView(spot: spot)
                    } label: {
                        SpotCard(
                            spot: spot,
                            distanceMiles: distance(to: spot),
                            isActive: spots.selectedSpotID == spot.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var ospSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Ramps & Public Spots", systemImage: "car.fill")
            GlassCard {
                if osm.isLoading && osm.ramps.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Loading nearby ramps & piers…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if osm.ramps.isEmpty {
                    Text("No public ramps or fishing sites tagged within 25 mi.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(osm.ramps.prefix(8)) { pin in
                            RampRow(pin: pin, distanceMiles: distance(to: pin))
                        }
                        attribution
                    }
                }
            }
        }
    }

    private var attribution: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(.caption2)
            Text("Community-tagged — quality varies. Data © OpenStreetMap.")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "My Saved Spots", systemImage: "mappin.and.ellipse")
            VStack(spacing: 10) {
                ForEach(spots.spots) { spot in
                    NavigationLink {
                        SpotDetailView(spot: spot)
                    } label: {
                        SpotCard(
                            spot: spot,
                            distanceMiles: distance(to: spot),
                            isActive: spots.selectedSpotID == spot.id
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            spots.remove(spot)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func distance(to spot: FishingSpot) -> Double? {
        guard let here = location.location else { return nil }
        return here.distance(from: spot.location) / 1609.34
    }

    private func distance(to pin: RampPin) -> Double? {
        guard let here = location.location else { return nil }
        return here.distance(from: pin.location) / 1609.34
    }
}

// MARK: - Ramp row

private struct RampRow: View {
    let pin: RampPin
    let distanceMiles: Double?

    var body: some View {
        Button {
            openInMaps()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: pin.kind.symbolName)
                    .foregroundStyle(.teal)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.name ?? pin.kind.displayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(pin.kind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let distanceMiles {
                    Text("\(Int(distanceMiles)) mi")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.up.right.circle")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func openInMaps() {
        let item = MKMapItem(location: pin.location, address: nil)
        item.name = pin.name ?? pin.kind.displayName
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}

// MARK: - Add spot

private struct AddSpotSheet: View {
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var waterType: WaterType = .freshwater
    @State private var kind: SpotKind = .other
    @State private var notes: String = ""
    @State private var targets: Set<Species> = []

    var onAdd: (FishingSpot) -> Void

    private var coordinate: CLLocation? { location.location }
    private var canSave: Bool {
        coordinate != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var speciesChoices: [Species] {
        Species.allCases.filter { $0 != .all && $0.isAvailable(for: waterType) }
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("e.g. North Cove", text: $name)
            }
            Section("Type") {
                Picker("Water type", selection: $waterType) {
                    ForEach(WaterType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Picker("Spot kind", selection: $kind) {
                    ForEach(SpotKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
            }
            Section("Target species") {
                ForEach(speciesChoices) { species in
                    Button {
                        toggle(species)
                    } label: {
                        HStack {
                            Circle().fill(species.tint).frame(width: 10, height: 10)
                            Text(species.displayName)
                            Spacer()
                            if targets.contains(species) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            Section("Notes (optional)") {
                TextField("Access notes, time of day, …", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
            if coordinate == nil {
                Section {
                    Label("Waiting on location…", systemImage: "location.slash")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Add Spot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(!canSave)
            }
        }
        .onChange(of: waterType) {
            // Drop targets that don't match the new water type.
            targets = targets.filter { $0.isAvailable(for: waterType) }
        }
    }

    private func toggle(_ species: Species) {
        if targets.contains(species) {
            targets.remove(species)
        } else {
            targets.insert(species)
        }
    }

    private func save() {
        guard let coordinate else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let spot = FishingSpot(
            name: trimmed,
            location: coordinate,
            waterType: waterType,
            kind: kind,
            stateCode: nil,
            targetSpecies: targets.isEmpty ? nil : Array(targets),
            notes: notes.isEmpty ? nil : notes
        )
        onAdd(spot)
        dismiss()
    }
}
