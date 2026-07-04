import Foundation
import Observation

/// Persists the user's smart-alert preferences (UserDefaults, JSON) and exposes
/// them as observable state for the settings UI and the scheduling wiring.
@MainActor
@Observable
final class AlertSettings {
    var preferences: AlertPreferences {
        didSet { persist() }
    }

    private let key = "alertPreferences"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AlertPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = .default
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
