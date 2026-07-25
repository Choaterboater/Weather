import SwiftUI

/// App settings, presented as a sheet from the Fishing tab. Currently home to
/// smart bite alerts; a natural place for future preferences.
struct SettingsView: View {
    @Environment(AlertSettings.self) private var settings
    @Environment(WeatherStore.self) private var weather
    @Environment(\.dismiss) private var dismiss

    /// Weather-derived notifications carry no room for WeatherKit's required
    /// combined mark and legal link, so they are only permitted on the NWS
    /// path. Whenever the active forecast is Apple-sourced, an enabled toggle
    /// would otherwise deliver nothing with no explanation.
    private var alertsArePaused: Bool {
        settings.preferences.enabled
            && !WeatherDerivedNotificationPolicy.allows(weather.provenance)
    }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Toggle("Bite alerts", isOn: $settings.preferences.enabled)
                    if settings.preferences.enabled {
                        Picker("Only windows scoring", selection: $settings.preferences.minScore) {
                            ForEach([60, 70, 80, 90], id: \.self) { Text("\($0)+").tag($0) }
                        }
                        Picker("Notify before", selection: $settings.preferences.leadMinutes) {
                            ForEach([15, 30, 45, 60, 90], id: \.self) { Text("\($0) min").tag($0) }
                        }
                    }
                    if alertsArePaused {
                        Label {
                            Text("Paused for this forecast. Bite alerts can only be sent while the National Weather Service is the active source.")
                        } icon: {
                            Image(systemName: "bell.slash")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.alertsPaused")
                    }
                } header: {
                    Text("Smart alerts")
                } footer: {
                    Text("Get a heads-up before the week's best fishing windows. Alerts refresh each time you open Plan the Week.")
                }

                Section("About") {
                    NavigationLink {
                        LegalCenterView()
                    } label: {
                        Label("Legal & Support", systemImage: "checkmark.shield.fill")
                    }
                    .accessibilityIdentifier("settings.legalSupport")
                    .accessibilityHint("Opens privacy, terms, support, and third-party notices")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Turning alerts off should clear any already-scheduled ones, even
            // if the user never re-opens the planner.
            .onChange(of: settings.preferences.enabled) { _, enabled in
                if !enabled {
                    Task {
                        await BiteAlertNotifier.clearAllWeatherDerivedNotifications()
                    }
                }
            }
        }
    }
}
