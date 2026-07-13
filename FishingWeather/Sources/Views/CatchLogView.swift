import SwiftUI
import UIKit

struct CatchLogView: View {
    @Environment(CatchLog.self) private var log
    @State private var showingForm = false
    @State private var errorTitle = "Catch History Needs Attention"
    @State private var deleteErrorMessage: String?

    var body: some View {
        Group {
            if log.entries.isEmpty {
                ContentUnavailableView {
                    Label("No catches yet", systemImage: "book.closed")
                } description: {
                    Text("Log a catch to start tracking what's working.")
                } actions: {
                    Button {
                        showingForm = true
                    } label: {
                        Label("Log a Catch", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            } else {
                List {
                    StatsSection(log: log)
                    Section("Catches") {
                        ForEach(log.entries) { entry in
                            CatchRow(entry: entry)
                        }
                        .onDelete(perform: delete)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Ink.backdrop)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingForm = true } label: {
                    Label("Log Catch", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingForm) {
            LogCatchView()
        }
        .onAppear {
            if let message = log.lastErrorMessage {
                errorTitle = "Catch History Needs Attention"
                deleteErrorMessage = message
            }
        }
        .alert(errorTitle, isPresented: showingDeleteError) {
            Button("OK", role: .cancel) {
                deleteErrorMessage = nil
                log.clearError()
            }
        } message: {
            Text(deleteErrorMessage ?? "The catch was kept. Please try again.")
        }
        .sensoryFeedback(.success, trigger: log.entries.count)
    }

    private func delete(_ offsets: IndexSet) {
        let selected = offsets.compactMap { index in
            log.entries.indices.contains(index) ? log.entries[index] : nil
        }
        for entry in selected {
            let operation = CatchOperationUIState.perform {
                try log.remove(entry)
            }
            if !operation.committed {
                // Each removal is transactional. Stop at the first failure and
                // tell the angler which operation did not commit.
                errorTitle = "Couldn't Delete Catch"
                deleteErrorMessage = log.lastErrorMessage
                    ?? operation.alertMessage
                    ?? "The catch was kept. Please try again."
                break
            }
        }
    }

    private var showingDeleteError: Binding<Bool> {
        Binding(
            get: { deleteErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    deleteErrorMessage = nil
                    log.clearError()
                }
            }
        )
    }
}

private struct StatsSection: View {
    let log: CatchLog

    var body: some View {
        Section {
            HStack {
                Stat(title: "Catches", value: "\(log.entries.count)")
                if let species = log.topSpecies {
                    Divider()
                    Stat(title: "Top species", value: species.displayName)
                }
                if let bait = log.topBait {
                    Divider()
                    Stat(title: "Top bait", value: bait)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct Stat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Ink.chart)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Ink.chartDim)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CatchRow: View {
    @Environment(CatchLog.self) private var log
    let entry: CatchEntry

    /// Loaded asynchronously so a row never does file I/O or a full-resolution
    /// decode on the main actor while the list scrolls.
    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.species.displayName)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Ink.chart)
                    if let size = entry.sizeSummary {
                        Text(size)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    }
                }
                if !entry.bait.isEmpty {
                    Text(entry.bait)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.chartDim)
                }
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.hullLine)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .task(id: entry.photoFilename) {
            image = await log.thumbnail(for: entry)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(.rect(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(entry.species.tint.opacity(0.25))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "fish.fill")
                        .foregroundStyle(entry.species.tint)
                }
        }
    }

    private var subtitle: String {
        var parts = [entry.date.formatted(date: .abbreviated, time: .shortened)]
        if let pressure = entry.pressureTendency { parts.append("\(pressure) pressure") }
        if let spot = entry.spotName { parts.append(spot) }
        return parts.joined(separator: " · ")
    }
}
