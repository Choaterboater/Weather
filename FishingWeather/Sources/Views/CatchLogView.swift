import SwiftUI
import UIKit

struct CatchLogView: View {
    @Environment(CatchLog.self) private var log
    @State private var showingForm = false

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
                        .onDelete { offsets in
                            offsets.map { log.entries[$0] }.forEach(log.remove)
                        }
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
        .sensoryFeedback(.success, trigger: log.entries.count)
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
                        .font(.headline)
                    if let size = entry.sizeSummary {
                        Text(size)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !entry.bait.isEmpty {
                    Text(entry.bait)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
