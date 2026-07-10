import CoreLocation
import SwiftUI

/// Reusable card row for any FishingSpot — used in the curated list, saved list,
/// and the active-spot summary. Uses the app's Liquid Glass aesthetic.
struct SpotCard: View {
    let spot: FishingSpot
    let distanceMiles: Double?
    let isActive: Bool

    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: spot.kind?.symbolName ?? "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(spot.waterType?.tint ?? .teal)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill((spot.waterType?.tint ?? .teal).opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(spot.name)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.chart)
                            .lineLimit(2)
                        Spacer()
                        if isActive {
                            Label("Active", systemImage: "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.green)
                                .font(.headline)
                        }
                    }

                    HStack(spacing: 6) {
                        if let kind = spot.kind {
                            chip(kind.displayName)
                        }
                        if let water = spot.waterType {
                            chip(water.displayName, color: water.tint)
                        }
                        if let stateCode = spot.stateCode {
                            chip(stateCode)
                        }
                        if let distanceMiles {
                            Text("· \(Int(distanceMiles)) mi")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Ink.chartDim)
                        }
                    }

                    if let targets = spot.targetSpecies, !targets.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(targets) { species in
                                    speciesChip(species)
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }
                }
            }
        }
    }

    private func chip(_ text: String, color: Color = Ink.chartDim) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color == Ink.chartDim ? Ink.chartDim : color)
    }

    private func speciesChip(_ species: Species) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(species.tint)
                .frame(width: 6, height: 6)
            Text(species.displayName)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Ink.chart)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(species.tint.opacity(0.12), in: .capsule)
    }
}
