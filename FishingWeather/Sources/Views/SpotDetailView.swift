import CoreLocation
import MapKit
import SwiftUI

/// Drill-down detail for a fishing spot. Shows a map, water type/kind/distance
/// header, target species, the relevant state regulations, notes, and actions
/// to set the spot active or get directions.
struct SpotDetailView: View {
    let spot: FishingSpot
    @Environment(SpotStore.self) private var spots
    @Environment(LocationManager.self) private var location
    @Environment(RegulationStore.self) private var regulations
    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition
    @AppStorage("spotMapStyle") private var mapStyleRaw = SpotMapStyle.standard.rawValue

    init(spot: FishingSpot) {
        self.spot = spot
        _cameraPosition = State(initialValue: .region(
            MKCoordinateRegion(
                center: spot.location.coordinate,
                latitudinalMeters: 2500,
                longitudinalMeters: 2500
            )
        ))
    }

    private var isActive: Bool {
        guard let active = spots.selectedSpot else { return false }
        return active.id == spot.id || active.isSamePlace(as: spot)
    }

    private var distanceMiles: Double? {
        guard let here = location.location else { return nil }
        return here.distance(from: spot.location) / 1609.34
    }

    private var stateInfo: StateRegulations? {
        guard let code = spot.stateCode else { return nil }
        return regulations.stateInfo(code)
    }

    var body: some View {
        ScrollView {
            GlassCardStack(spacing: 18) {
                map
                header
                if let targets = spot.targetSpecies, !targets.isEmpty {
                    speciesSection(targets)
                }
                if let notes = spot.notes, !notes.isEmpty {
                    notesCard(notes)
                }
                if let code = spot.stateCode {
                    regulationsSection(stateCode: code)
                }
                actions
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle(spot.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var map: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            Marker(spot.name, coordinate: spot.location.coordinate)
                .tint(spot.waterType?.tint ?? .teal)
        }
        .mapStyle(SpotMapStyle.stored($mapStyleRaw).wrappedValue.mapStyle)
        .frame(height: 320)
        .clipShape(.rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Ink.hullLine, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            MapStylePicker(selection: SpotMapStyle.stored($mapStyleRaw))
                .padding(8)
        }
    }

    private var header: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: spot.kind?.symbolName ?? "mappin.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(spot.waterType.flatMap { $0.tint } ?? Ink.tide)
                    VStack(alignment: .leading) {
                        Text(spot.name)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.chart)
                        Text(headerSubtitle)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    }
                    Spacer()
                }
                if let distanceMiles {
                    Label("\(Int(distanceMiles)) miles from you", systemImage: "location")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
                }
            }
        }
    }

    private var headerSubtitle: String {
        var parts: [String] = []
        if let kind = spot.kind { parts.append(kind.displayName) }
        if let water = spot.waterType { parts.append(water.displayName) }
        if let stateCode = spot.stateCode { parts.append(stateCode) }
        return parts.joined(separator: " · ")
    }

    private func speciesSection(_ species: [Species]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Target Species", systemImage: "fish.fill")
            GlassCard {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(species) { species in
                        HStack(spacing: 6) {
                            Circle().fill(species.tint).frame(width: 8, height: 8)
                            Text(species.displayName)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(Ink.chart)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(species.tint.opacity(0.12), in: .rect(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Notes", systemImage: "text.book.closed")
            GlassCard {
                Text(notes)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.chartDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func regulationsSection(stateCode: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Regulations · \(stateCode)", systemImage: "ruler")
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    if let targets = spot.targetSpecies {
                        ForEach(targets) { species in
                            if let reg = regulations.regulation(for: species, in: stateCode) {
                                RegulationRow(species: species, regulation: reg)
                            }
                        }
                    }
                    if let info = stateInfo {
                        stateFootnote(info)
                    }
                }
            }
        }
    }

    private func stateFootnote(_ info: StateRegulations) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                Text("Verified \(info.lastVerifiedDate). Always confirm at the agency before keeping fish.")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(Ink.chartDim)
            Link(destination: info.sourceURL) {
                Label(info.stateName + " agency", systemImage: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                if isActive {
                    spots.select(nil)
                } else {
                    spots.activate(spot)
                }
                dismiss()
            } label: {
                Label(
                    isActive ? "Active spot — use current location instead" : "Set as active",
                    systemImage: isActive ? "checkmark.circle.fill" : "mappin.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(isActive ? .secondary : .teal)

            Button {
                openInMaps()
            } label: {
                Label("Get directions", systemImage: "car")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    private func openInMaps() {
        let item = MKMapItem(location: spot.location, address: nil)
        item.name = spot.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}

private struct RegulationRow: View {
    let species: Species
    let regulation: Regulation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(species.tint).frame(width: 8, height: 8)
                Text(species.displayName)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Ink.chart)
                Spacer()
                if regulation.isClosed(on: .now) {
                    Label("Closed", systemImage: "exclamationmark.octagon.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
            HStack(spacing: 14) {
                fact("Size", regulation.slotDescription ?? "—")
                fact("Bag", regulation.dailyBagLimit.map { "\($0)/day" } ?? "—")
            }
            if !regulation.seasonClosures.isEmpty {
                ForEach(Array(regulation.seasonClosures.enumerated()), id: \.offset) { _, closure in
                    Label(closure.label, systemImage: "calendar")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
                }
            }
            if let notes = regulation.notes {
                Text(notes)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.chartDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Ink.chartDim)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Ink.chart)
        }
    }
}
