import CoreLocation
import PhotosUI
import SwiftUI
import UIKit

struct ScoutView: View {
    @Environment(WeatherStore.self) private var weather
    @Environment(SpotStore.self) private var spots
    @Environment(LocationManager.self) private var location
    @AppStorage("selectedSpecies") private var species: Species = .all

    @State private var scout = WaterScout()
    @State private var image: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    private var liveConditions: FishingConditions? {
        guard let loc = spots.selectedSpot?.location ?? location.location,
              weather.hasData(for: loc) else { return nil }
        return weather.conditions
    }

    var body: some View {
        ScrollView {
            GlassCardStack(spacing: 20) {
                introCard
                imageArea
                actions
                resultArea
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Ink.backdrop)
        .animation(.smooth(duration: 0.35), value: scout.status)
        .sensoryFeedback(trigger: scout.status) { _, newValue in
            switch newValue {
            case .ready: .success
            case .failed: .error
            default: nil
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { captured in
                image = captured
                analyze(captured)
            }
            .ignoresSafeArea()
        }
        .task(id: pickerItem) {
            guard let selectedItem = pickerItem,
                  let data = try? await selectedItem.loadTransferable(type: Data.self),
                  !Task.isCancelled,
                  pickerItem == selectedItem,
                  let picked = UIImage(data: data)
            else { return }
            image = picked
            analyze(picked)
        }
        .onChange(of: species) {
            scout.reset()
            if let image { analyze(image) }
        }
    }

    private var introCard: some View {
        GlassCard {
            Text("Snap the water in front of you. The on-device AI reads the scene and your conditions to suggest where to cast.")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Ink.chartDim)
        }
    }

    @ViewBuilder
    private var imageArea: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 20))
        } else {
            LinearGradient(
                colors: [Ink.hullLine.opacity(0.3), Ink.abyss.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Ink.hullLine, lineWidth: 1)
            )
            .overlay {
                Image(systemName: "water.waves")
                    .font(.system(size: 44))
                    .foregroundStyle(Ink.chartDim.opacity(0.5))
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if CameraPicker.isAvailable {
                Button {
                    showCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
    }

    @ViewBuilder
    private var resultArea: some View {
        switch scout.status {
        case .idle:
            EmptyView()
        case .working:
            GlassCard {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Reading the water…")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
                }
            }
        case .unavailable(let message):
            GlassCard {
                Label(message, systemImage: "exclamationmark.bubble")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.chartDim)
            }
        case .failed(let message):
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Couldn't read this photo", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Ink.chart)
                    Text(message)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
                }
            }
        case .ready:
            if let report = scout.report {
                ScoutReportCard(report: report)
            }
        }
    }

    private func analyze(_ image: UIImage) {
        Task { await scout.analyze(image: image, species: species, conditions: liveConditions) }
    }
}

private struct ScoutReportCard: View {
    let report: WaterScoutReport

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Best cast")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Ink.chart)
                    Spacer()
                    Text("\(report.rating)/100")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .contentTransition(.numericText())
                        .foregroundStyle(Ink.band(for: report.rating))
                }
                Text(report.bestSpot)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.chartDim)

                Divider()

                LabeledRow(label: "Structure", value: report.structure, systemImage: "square.stack.3d.up")
                LabeledRow(label: "Approach", value: report.approach, systemImage: "figure.fishing")
                LabeledRow(label: "Heads up", value: report.notes, systemImage: "lightbulb")
            }
        }
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Ink.chartDim)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Ink.chartDim)
                Text(value)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.chart)
            }
        }
    }
}
