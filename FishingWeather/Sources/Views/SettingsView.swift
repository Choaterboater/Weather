import SwiftUI

/// App settings, presented as a sheet from the Fishing tab. Currently home to
/// smart bite alerts; a natural place for future preferences.
struct SettingsView: View {
    @Environment(AlertSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

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
