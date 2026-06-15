import SwiftUI

struct LocationPromptView: View {
    let onRequest: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Find your spot", systemImage: "location.circle")
        } description: {
            Text("Fishing Weather needs your location to show local conditions and forecasts.")
        } actions: {
            Button("Use My Location", action: onRequest)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct LocationDeniedView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Location is off", systemImage: "location.slash")
        } description: {
            Text("Enable location access for Fishing Weather in Settings to see local conditions.")
        } actions: {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
