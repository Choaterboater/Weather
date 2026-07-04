import PhotosUI
import SwiftUI
import UIKit

struct ScoutView: View {
    @Environment(WeatherStore.self) private var weather
    @AppStorage("selectedSpecies") private var species: Species = .all

    @State private var scout = WaterScout()
    @State private var image: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                introCard
                imageArea
                actions
                resultArea
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background {
            Color(.systemBackground)
            LinearGradient(colors: [.blue.opacity(0.3), .teal.opacity(0.12)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
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
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let picked = UIImage(data: data) {
                    image = picked
                    analyze(picked)
                }
            }
        }
    }

    private var introCard: some View {
        GlassCard {
            Text("Snap the water in front of you. The on-device AI reads the scene and your conditions to suggest where to cast.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            RoundedRectangle(cornerRadius: 20)
                .fill(.quaternary)
                .frame(height: 220)
                .overlay {
                    Image(systemName: "water.waves")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
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
                .buttonStyle(.borderedProminent)
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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
                    Text("Reading the water…").foregroundStyle(.secondary)
                }
            }
        case .unavailable(let message):
            GlassCard {
                Label(message, systemImage: "exclamationmark.bubble")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Couldn't read this photo", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.medium))
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        case .ready:
            if let report = scout.report {
                ScoutReportCard(report: report)
            }
        }
    }

    private func analyze(_ image: UIImage) {
        Task { await scout.analyze(image: image, species: species, conditions: weather.conditions) }
    }
}

private struct ScoutReportCard: View {
    let report: WaterScoutReport

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Best cast")
                        .font(.headline)
                    Spacer()
                    Text("\(report.rating)/100")
                        .font(.headline)
                        .contentTransition(.numericText())
                        .foregroundStyle(report.rating >= 60 ? .green : (report.rating >= 35 ? .orange : .red))
                }
                Text(report.bestSpot)
                    .font(.subheadline)

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
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
            }
        }
    }
}
