import CoreLocation
import SwiftUI

enum AppDestination: String, CaseIterable, Hashable, Sendable {
    case community
    case map
    case biteTime
    case you

    static let defaultDestination = AppDestination.biteTime

    static func migrating(storedValue: String) -> AppDestination {
        if let destination = AppDestination(rawValue: storedValue) {
            return destination
        }

        return switch storedValue {
        case "weather", "fishing": .biteTime
        case "spots": .map
        case "guide", "log", "scout": .you
        default: defaultDestination
        }
    }

    var title: String {
        switch self {
        case .community: "Community"
        case .map: "Map"
        case .biteTime: "BiteTime"
        case .you: "You"
        }
    }

    var systemImage: String {
        switch self {
        case .community: "person.3.fill"
        case .map: "map.fill"
        case .biteTime: "clock.badge.fill"
        case .you: "person.crop.circle.fill"
        }
    }

    var accessibilityIdentifier: String {
        "tab.\(rawValue)"
    }
}

struct MainTabView: View {
    @Environment(LocationManager.self) private var location
    @Environment(SpotStore.self) private var spots
    @Environment(WeatherStore.self) private var weather
    @Environment(TideService.self) private var tides

    @AppStorage("selectedTab") private var storedSelection = AppDestination.defaultDestination.rawValue
    @State private var showsLogCatch = false

    private var selectedDestination: AppDestination {
        AppDestination.migrating(storedValue: storedSelection)
    }

    private var destinationSelection: Binding<AppDestination> {
        Binding {
            selectedDestination
        } set: { destination in
            storedSelection = destination.rawValue
        }
    }

    /// Pull-to-refresh must bypass the stores' caches — a location nudge alone
    /// no longer re-keys the load tasks.
    private func refresh() async {
        location.refresh()
        guard let active = spots.selectedSpot?.location ?? location.location else { return }
        await weather.load(for: active, force: true)
        await tides.load(near: active, force: true)
    }

    var body: some View {
        TabView(selection: destinationSelection) {
            Tab(value: AppDestination.community) {
                NavigationStack {
                    CommunityPlaceholderView {
                        storedSelection = AppDestination.map.rawValue
                    }
                    .navigationTitle(AppDestination.community.title)
                    .navigationBarTitleDisplayMode(.large)
                }
            } label: {
                destinationLabel(.community)
            }

            Tab(value: AppDestination.map) {
                NavigationStack {
                    SpotsView()
                        .navigationTitle(AppDestination.map.title)
                }
            } label: {
                destinationLabel(.map)
            }

            Tab(value: AppDestination.biteTime) {
                NavigationStack {
                    FishingView()
                        .navigationTitle(AppDestination.biteTime.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .refreshable { await refresh() }
                }
            } label: {
                destinationLabel(.biteTime)
            }

            Tab(value: AppDestination.you) {
                NavigationStack {
                    YouView()
                        .navigationTitle(AppDestination.you.title)
                        .navigationBarTitleDisplayMode(.large)
                }
            } label: {
                destinationLabel(.you)
            }
        }
        .overlay(alignment: .bottom) {
            logCatchAction
                .padding(.bottom, 20)
                .zIndex(1)
        }
        .sheet(isPresented: $showsLogCatch) {
            LogCatchView()
        }
        .onAppear(perform: migrateStoredSelection)
    }

    private func destinationLabel(_ destination: AppDestination) -> some View {
        Label(destination.title, systemImage: destination.systemImage)
            .accessibilityIdentifier(destination.accessibilityIdentifier)
    }

    private var logCatchAction: some View {
        Button {
            showsLogCatch = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Ink.abyss)
                    .frame(width: 54, height: 54)
                    .glassEffect(.regular.tint(Ink.brass).interactive(), in: .circle)
                Text("Log")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.chart)
            }
            .frame(minWidth: 64, minHeight: 68)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log Catch")
        .accessibilityHint("Opens a form without leaving \(selectedDestination.title)")
        .accessibilityIdentifier("action.logCatch")
    }

    private func migrateStoredSelection() {
        let migrated = AppDestination.migrating(storedValue: storedSelection).rawValue
        guard migrated != storedSelection else { return }
        storedSelection = migrated
    }
}
