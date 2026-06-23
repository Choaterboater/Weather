import CoreLocation
import SwiftUI

/// Single-species detail screen: hero, in-season indicator, regulations panel
/// (for the user-picked state), bait/technique guide, habitat & timing tips,
/// and recent iNaturalist sightings nearby.
struct SpeciesDetailView: View {
    let species: Species
    @Environment(SpotStore.self) private var spots
    @Environment(LocationManager.self) private var location
    @Environment(RegulationStore.self) private var regulations
    @Environment(INaturalistClient.self) private var inaturalist
    @AppStorage("selectedSpecies") private var selectedSpecies: Species = .all

    @State private var stateCode: String

    init(species: Species) {
        self.species = species
        _stateCode = State(initialValue: "FL")
    }

    private var here: CLLocation? {
        spots.selectedSpot?.location ?? location.location
    }

    private var sightings: [SpeciesSighting] {
        inaturalist.sightings[species] ?? []
    }

    private var profile: BaitProfile { BaitProfile.profile(for: species) }

    private var inferredState: String? {
        spots.selectedSpot?.stateCode
    }

    private var regulation: Regulation? {
        regulations.regulation(for: species, in: stateCode)
    }

    private var stateInfo: StateRegulations? {
        regulations.stateInfo(stateCode)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                inSeasonCard
                regulationsCard
                sightingsCard
                baitsCard
                techniquesCard
                habitatCard
                setFocusButton
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle(species.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let inferred = inferredState, regulations.stateInfo(inferred) != nil {
                stateCode = inferred
            } else if let first = regulations.loadedStateCodes.first {
                stateCode = first
            }
        }
        .task(id: sightingsKey) {
            guard let here else { return }
            await inaturalist.loadSightings(for: species, near: here)
        }
    }

    private var sightingsKey: String {
        guard let coord = here?.coordinate else { return "none" }
        let lat = (coord.latitude * 10).rounded() / 10
        let lon = (coord.longitude * 10).rounded() / 10
        return "\(species.rawValue)-\(lat),\(lon)"
    }

    // MARK: - Sections

    private var hero: some View {
        GlassCard {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [species.tint.opacity(0.4), species.tint.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                    Image(systemName: "fish.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(species.tint)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(species.displayName).font(.title2.weight(.semibold))
                    if let scientific = species.scientificName {
                        Text(scientific).italic().font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let waterType = species.waterType {
                        Label(waterType.displayName, systemImage: waterType.symbolName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private var inSeasonCard: some View {
        let inSeason = isInSeason(species: species, on: .now)
        return GlassCard {
            HStack(spacing: 12) {
                Image(systemName: inSeason ? "circle.fill" : "circle")
                    .foregroundStyle(inSeason ? .green : .orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(inSeason ? "Peak season right now" : "Off-peak this month")
                        .font(.subheadline.weight(.semibold))
                    Text(inSeason
                        ? "Local activity tends to peak — prioritize this species."
                        : "Still catchable. Check tides, weather, and the score on the Fishing tab."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
    }

    private var regulationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Regulations", systemImage: "ruler")
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    statePicker
                    if let regulation {
                        regulationDetail(regulation)
                    } else {
                        Text("No regulation data on file for \(species.displayName.lowercased()) in \(stateCode).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let info = stateInfo {
                        Divider()
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle").font(.caption2)
                            Text("Verified \(info.lastVerifiedDate). Always confirm before keeping fish.")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        Link(destination: info.sourceURL) {
                            Label("\(info.stateName) agency", systemImage: "arrow.up.right.square")
                                .font(.caption.weight(.medium))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statePicker: some View {
        if regulations.loadedStateCodes.count > 1 {
            Picker("State", selection: $stateCode) {
                ForEach(regulations.loadedStateCodes, id: \.self) { code in
                    Text(regulations.stateInfo(code)?.stateName ?? code).tag(code)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func regulationDetail(_ reg: Regulation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                fact("Size", reg.slotDescription ?? "—")
                Spacer()
                fact("Bag", reg.dailyBagLimit.map { "\($0)/day" } ?? "—")
                Spacer()
                fact("Water", reg.waterType.displayName)
                Spacer()
            }
            if reg.isClosed(on: .now) {
                Label("Closed today", systemImage: "exclamationmark.octagon.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.red)
            }
            if !reg.seasonClosures.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(reg.seasonClosures.enumerated()), id: \.offset) { _, closure in
                        Label(closure.label, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let notes = reg.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var sightingsCard: some View {
        if here != nil {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Recently Seen Nearby", systemImage: "binoculars")
                GlassCard {
                    if inaturalist.isLoading.contains(species) && sightings.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Searching iNaturalist…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if sightings.isEmpty {
                        Text("No verified observations within 50 mi in the last year.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(sightings.prefix(4)) { sighting in
                                SightingRow(sighting: sighting, from: here)
                            }
                            attribution
                        }
                    }
                }
            }
        }
    }

    private var attribution: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle").font(.caption2)
            Text("Community observations · iNaturalist")
                .font(.caption2)
            Spacer()
            Link(destination: URL(string: "https://www.inaturalist.org")!) {
                Text("inaturalist.org")
                    .font(.caption2.weight(.medium))
            }
        }
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private var baitsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Top Baits", systemImage: "fish.circle")
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(profile.baits, id: \.self) { bait in
                        Label(bait, systemImage: "circle.fill")
                            .labelStyle(BulletLabelStyle(color: species.tint))
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var techniquesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Techniques", systemImage: "lasso")
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(profile.techniques, id: \.self) { technique in
                        Label(technique, systemImage: "circle.fill")
                            .labelStyle(BulletLabelStyle(color: species.tint))
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var habitatCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Where & When", systemImage: "scope")
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label(profile.habitatHint, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Label(profile.bestTimeOfDay, systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var setFocusButton: some View {
        Button {
            selectedSpecies = species
        } label: {
            Label(
                selectedSpecies == species ? "Already your focus" : "Set as Fishing tab focus",
                systemImage: selectedSpecies == species ? "checkmark.circle.fill" : "target"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(selectedSpecies == species ? .secondary : species.tint)
        .disabled(selectedSpecies == species)
    }

    // MARK: - Helpers

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func isInSeason(species: Species, on date: Date) -> Bool {
        // Same data the scorer uses; duplicated as a small local table to
        // avoid coupling to the scorer's internals.
        let month = Calendar.current.component(.month, from: date)
        let peaks: Set<Int>
        switch species {
        case .all: return true
        case .bass: peaks = [3, 4, 5, 6, 9, 10, 11]
        case .crappie: peaks = [2, 3, 4, 5]
        case .catfish: peaks = [5, 6, 7, 8, 9]
        case .bluegill: peaks = [5, 6, 7, 8]
        case .redfish: peaks = [9, 10, 11]
        case .speckledTrout: peaks = [3, 4, 5, 10, 11]
        case .pompano: peaks = [3, 4, 5, 6, 10, 11]
        case .flounder: peaks = [9, 10, 11]
        case .sheepshead: peaks = [2, 3, 4]
        case .snook: peaks = [4, 5, 6, 7, 8, 9]
        case .mangroveSnapper: peaks = [5, 6, 7, 8, 9]
        }
        return peaks.contains(month)
    }
}

private struct SightingRow: View {
    let sighting: SpeciesSighting
    let from: CLLocation?

    private var distanceMiles: Double? {
        guard let from else { return nil }
        return from.distance(from: sighting.location) / 1609.34
    }

    private var dateText: String {
        sighting.observedOn.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(dateText)
                    .font(.subheadline.weight(.medium))
                if let place = sighting.placeGuess {
                    Text(place)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let distanceMiles {
                Text("\(Int(distanceMiles)) mi")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = sighting.thumbnailURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "fish")
                        .foregroundStyle(.secondary)
                default:
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(.rect(cornerRadius: 8))
        } else {
            Image(systemName: "fish")
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color.secondary.opacity(0.15), in: .rect(cornerRadius: 8))
        }
    }
}

private struct BulletLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            configuration.title
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
