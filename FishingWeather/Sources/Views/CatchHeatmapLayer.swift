import MapKit
import SwiftUI

/// Draws a heatmap overlay on a Map for a given list of `CatchEntry`.
struct CatchHeatmapLayer: MapContent {
    let entries: [CatchEntry]
    
    var body: some MapContent {
        ForEach(entries.filter { $0.latitude != nil && $0.longitude != nil }) { catchEntry in
            MapCircle(
                center: CLLocationCoordinate2D(latitude: catchEntry.latitude!, longitude: catchEntry.longitude!),
                radius: CLLocationDistance(exactly: 150)!
            )
            .foregroundStyle(Ink.bite.opacity(0.4))
            .stroke(Ink.bite, lineWidth: 1)
        }
    }
}
