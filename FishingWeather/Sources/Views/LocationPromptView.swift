import SwiftUI
import UIKit

struct LocationPromptView: View {
    let onRequest: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Find your spot", systemImage: "location.circle")
        } description: {
            Text("BiteCast needs your location to show local conditions and forecasts.")
        } actions: {
            Button("Use My Location", action: onRequest)
                .buttonStyle(.glassProminent)
        }
    }
}

struct LocationDeniedView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Location is off", systemImage: "location.slash")
        } description: {
            Text("Enable location access for BiteCast in Settings to see local conditions.")
        } actions: {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .buttonStyle(.glassProminent)
            }
        }
    }
}
