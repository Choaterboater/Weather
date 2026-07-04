import Foundation

/// Shares the latest bite reading between the app and its Home Screen widget
/// through the App Group container. Both read and write degrade to a no-op if
/// the group isn't reachable, so the app is never blocked on widget plumbing.
enum WidgetSnapshotStore {
    static let appGroup = "group.app.choatelabs.bitecast"
    private static let key = "widgetSnapshot"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func read() -> WidgetSnapshot? {
        guard let defaults, let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }
}
