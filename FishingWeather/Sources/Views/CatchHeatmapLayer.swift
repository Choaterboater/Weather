import MapKit
import SwiftUI

/// Draws a heatmap overlay on a Map for a given list of `CatchEntry`. Overlapping
/// semi-transparent circles alpha-composite, so denser catch clusters read hotter.
struct CatchHeatmapLayer: MapContent {
    let entries: [CatchEntry]

    /// Pre-resolve to plottable points so the map content has no optionals.
    private struct Point: Identifiable {
        let id: UUID
        let coordinate: CLLocationCoordinate2D
    }

    private var points: [Point] {
        entries.compactMap { entry in
            guard let lat = entry.latitude, let lon = entry.longitude else { return nil }
            return Point(id: entry.id, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    var body: some MapContent {
        ForEach(points) { point in
            MapCircle(center: point.coordinate, radius: 150)
                .foregroundStyle(Ink.bite.opacity(0.4))
                .stroke(Ink.bite, lineWidth: 1)
        }
    }
}
