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

    @Environment(CatchLog.self) private var log
    @State private var showsAddSheet = false
    @State private var routedSpot: FishingSpot?
    @AppStorage("showsHeatmap") private var showsHeatmap = true
    @AppStorage("spotMapStyle") private var mapStyleRaw = SpotMapStyle.standard.rawValue

    private var here: CLLocation? {
        spots.selectedSpot?.location ?? location.location
    }

    private var curated: [FishingSpot] {
        guard let here else { return [] }
        return catalog.nearby(here)
    }

    var body: some View {
        ScrollView {
            GlassCardStack(spacing: 18) {
                overviewMapSection
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
        .navigationDestination(item: $routedSpot) { spot in
            SpotDetailView(spot: spot)
        }
        .background(Ink.backdrop)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
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
        .refreshable {
            guard let here else { return }
            await osm.loadRamps(near: here)
        }
    }

    private var hereKey: String {
        guard let coord = here?.coordinate else { return "none" }
        // Match OpenStreetMapClient's 0.1° tile (~7 mi), not whole degrees.
        let lat = (coord.latitude * 10).rounded() / 10
        let lon = (coord.longitude * 10).rounded() / 10
        return "\(lat),\(lon)"
    }

    // MARK: - Sections

    @ViewBuilder
    private var overviewMapSection: some View {
        if let here {
            ZStack(alignment: .topTrailing) {
                SpotsOverviewMap(
                    center: here.coordinate,
                    annotations: mapAnnotations,
                    catchEntries: log.entries,
                    showsHeatmap: showsHeatmap,
                    style: SpotMapStyle.stored($mapStyleRaw),
                    onSelect: handleMapSelection
                )
                
                if !log.entries.filter({ $0.latitude != nil }).isEmpty {
                    Button {
                        showsHeatmap.toggle()
                    } label: {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(showsHeatmap ? Ink.bite : .white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: .circle)
                    }
                    .padding(8)
                }
            }
        }
    }

    /// Curated + saved spots (which drill into detail) plus OSM ramps (which
    /// open in Maps), unified into map pins. Saved spots win when a curated
    /// entry is the same place (stable catalog ids would otherwise collide).
    private var mapAnnotations: [SpotAnnotation] {
        var uniqueSpots: [FishingSpot] = []
        for spot in spots.spots + curated {
            if !uniqueSpots.contains(where: { $0.id == spot.id || $0.isSamePlace(as: spot) }) {
                uniqueSpots.append(spot)
            }
        }
        let spotPins = uniqueSpots.map { spot in
            SpotAnnotation(
                id: "spot-\(spot.id.uuidString)",
                coordinate: spot.location.coordinate,
                title: spot.name,
                symbol: spot.kind?.symbolName ?? "mappin",
                color: spot.waterType?.tint ?? .teal,
                payload: .spot(spot)
            )
        }
        let rampPins = osm.ramps.prefix(20).map { pin in
            SpotAnnotation(
                id: "ramp-\(pin.id)",
                coordinate: pin.location.coordinate,
                title: pin.name ?? pin.kind.displayName,
                symbol: pin.kind.symbolName,
                color: .brown,
                payload: .ramp(pin)
            )
        }
        return spotPins + rampPins
    }

    private func handleMapSelection(_ annotation: SpotAnnotation) {
        switch annotation.payload {
        case .spot(let spot): routedSpot = spot
        case .ramp(let pin): openInMaps(pin)
        }
    }

    private func openInMaps(_ pin: RampPin) {
        let item = MKMapItem(location: pin.location, address: nil)
        item.name = pin.name ?? pin.kind.displayName
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

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
                                .font(.system(size: 24))
                                .foregroundStyle(Ink.brass)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Ink.brass.opacity(0.15)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Current Location")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Ink.chart)
                                if location.descriptor.displayName != "Current Location" {
                                    Text(location.descriptor.displayName)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Ink.chartDim)
                                }
                            }
                            Spacer()
                            if spots.selectedSpotID == nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Ink.bite)
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
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
                            isActive: spots.selectedSpot.map { $0.id == spot.id || $0.isSamePlace(as: spot) } ?? false
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
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if osm.ramps.isEmpty, osm.lastError != nil {
                    // A failed request is not "no ramps here" — don't present
                    // a network error as an authoritative empty area.
                    HStack {
                        Label("Couldn't load nearby ramps", systemImage: "wifi.slash")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                        Spacer()
                        Button("Retry") {
                            guard let here else { return }
                            Task { await osm.loadRamps(near: here) }
                        }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    }
                } else if osm.ramps.isEmpty {
                    Text("No public ramps or fishing sites tagged within 25 mi.")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
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
                .font(.system(size: 10, weight: .bold, design: .monospaced))
            Text("Community-tagged — quality varies. Data © OpenStreetMap.")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(Ink.chartDim)
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
                            isActive: spots.selectedSpot.map { $0.id == spot.id || $0.isSamePlace(as: spot) } ?? false
                        )
                    }
                    .buttonStyle(.plain)
                    // .swipeActions only works inside a List; in this ScrollView
                    // it silently did nothing, leaving no way to delete a spot.
                    .contextMenu {
                        Button(role: .destructive) {
                            spots.remove(spot)
                        } label: {
                            Label("Delete Spot", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func distance(to spot: FishingSpot) -> Double? {
        guard let here else { return nil }
        return here.distance(from: spot.location) / 1609.34
    }

    private func distance(to pin: RampPin) -> Double? {
        guard let here else { return nil }
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
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Ink.chart)
                        .lineLimit(1)
                    Text(pin.kind.displayName)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
                }
                Spacer()
                if let distanceMiles {
                    Text("\(Int(distanceMiles)) mi")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
                }
                Image(systemName: "arrow.up.right.circle")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Ink.hullLine)
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
                        .foregroundStyle(Ink.chartDim)
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
            stateCode: location.administrativeArea,
            targetSpecies: targets.isEmpty ? nil : Array(targets),
            notes: notes.isEmpty ? nil : notes
        )
        onAdd(spot)
        dismiss()
    }
}
