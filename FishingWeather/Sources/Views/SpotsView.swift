import SwiftUI

struct SpotsView: View {
    @Environment(SpotStore.self) private var spots
    @Environment(LocationManager.self) private var location

    @State private var newName = ""

    var body: some View {
        List {
            Section {
                SelectableRow(
                    title: "Current Location",
                    subtitle: location.placeName,
                    systemImage: "location.fill",
                    isSelected: spots.selectedSpotID == nil
                ) {
                    spots.select(nil)
                }
            }

            if !spots.spots.isEmpty {
                Section("Saved Spots") {
                    ForEach(spots.spots) { spot in
                        SelectableRow(
                            title: spot.name,
                            subtitle: nil,
                            systemImage: "mappin.circle.fill",
                            isSelected: spots.selectedSpotID == spot.id
                        ) {
                            spots.select(spot)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { spots.spots[$0] }.forEach(spots.remove)
                    }
                }
            }

            Section("Add a Spot") {
                TextField("Name (e.g. North Cove)", text: $newName)
                Button {
                    saveCurrentLocation()
                } label: {
                    Label("Save current location", systemImage: "plus.circle")
                }
                .disabled(location.location == nil || trimmedName.isEmpty)
            }
        }
    }

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveCurrentLocation() {
        guard let location = location.location else { return }
        spots.add(FishingSpot(name: trimmedName, location: location))
        newName = ""
    }
}

private struct SelectableRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .foregroundStyle(.primary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: systemImage)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
