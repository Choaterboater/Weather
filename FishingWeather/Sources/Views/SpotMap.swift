import CoreLocation
import MapKit
import SwiftUI

/// Basemap style shared by the Spots overview map and the spot-detail map,
/// persisted so the angler's preference sticks across both. MapKit ships no
/// nautical-chart basemap; hybrid (imagery + labels) is the closest for
/// reading shorelines and structure.
enum SpotMapStyle: String, CaseIterable, Identifiable {
    case standard, hybrid, satellite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Map"
        case .hybrid: "Hybrid"
        case .satellite: "Satellite"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic)
        case .hybrid: .hybrid(elevation: .realistic)
        case .satellite: .imagery(elevation: .realistic)
        }
    }
}

/// AppStorage-backed binding to the shared map style, so the overview and
/// detail maps agree without threading state through the view tree.
extension SpotMapStyle {
    @MainActor
    static func stored(_ raw: Binding<String>) -> Binding<SpotMapStyle> {
        Binding(
            get: { SpotMapStyle(rawValue: raw.wrappedValue) ?? .standard },
            set: { raw.wrappedValue = $0.rawValue }
        )
    }
}

/// A compact basemap switcher meant to float over a map corner.
struct MapStylePicker: View {
    @Binding var selection: SpotMapStyle

    var body: some View {
        Picker("Map style", selection: $selection) {
            ForEach(SpotMapStyle.allCases) { style in
                Text(style.label).tag(style)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 8))
        .frame(maxWidth: 280)
    }
}

/// One plottable point on the overview map. Unifies curated/saved spots (which
/// drill into a detail screen) and OSM ramps (which open in Maps).
struct SpotAnnotation: Identifiable {
    enum Payload {
        case spot(FishingSpot)
        case ramp(RampPin)
    }

    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    let symbol: String
    let color: Color
    let payload: Payload
}

/// Interactive map of every nearby spot and ramp. Tapping a pin calls back with
/// its annotation; the caller decides whether to navigate or open Maps.
struct SpotsOverviewMap: View {
    let center: CLLocationCoordinate2D
    let annotations: [SpotAnnotation]
    let catchEntries: [CatchEntry]
    let showsHeatmap: Bool
    @Binding var style: SpotMapStyle
    let onSelect: (SpotAnnotation) -> Void

    @State private var camera: MapCameraPosition
    @State private var selection: String?

    /// Opens framed on `center` (the active/device location) at roughly a
    /// 25-mile radius — the same neighborhood the curated/ramp data covers —
    /// rather than `.automatic`, which zooms out to the whole continent when
    /// there are no pins to frame.
    init(
        center: CLLocationCoordinate2D,
        annotations: [SpotAnnotation],
        catchEntries: [CatchEntry] = [],
        showsHeatmap: Bool = false,
        style: Binding<SpotMapStyle>,
        onSelect: @escaping (SpotAnnotation) -> Void
    ) {
        self.center = center
        self.annotations = annotations
        self.catchEntries = catchEntries
        self.showsHeatmap = showsHeatmap
        self._style = style
        self.onSelect = onSelect
        self._camera = State(initialValue: Self.region(for: center))
    }

    var body: some View {
        Map(position: $camera, selection: $selection) {
            UserAnnotation()
            
            if showsHeatmap {
                CatchHeatmapLayer(entries: catchEntries)
            }
            
            ForEach(annotations) { annotation in
                Marker(annotation.title, systemImage: annotation.symbol,
                       coordinate: annotation.coordinate)
                    .tint(annotation.color)
                    .tag(annotation.id)
            }
        }
        .mapStyle(style.mapStyle)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .frame(height: 440)
        .clipShape(.rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Ink.hullLine, lineWidth: 1))
        .overlay(alignment: .top) {
            MapStylePicker(selection: $style)
                .padding(8)
        }
        .onChange(of: center.latitude) { recenterToActive() }
        .onChange(of: center.longitude) { recenterToActive() }
        .onChange(of: selection) { _, newValue in
            guard let newValue,
                  let annotation = annotations.first(where: { $0.id == newValue })
            else { return }
            onSelect(annotation)
            // Clear so tapping the same pin again re-fires the callback.
            selection = nil
        }
        .accessibilityLabel("Map of nearby spots and ramps")
    }

    private func recenterToActive() {
        camera = Self.region(for: center)
    }

    private static func region(for center: CLLocationCoordinate2D) -> MapCameraPosition {
        .region(MKCoordinateRegion(
            center: center,
            latitudinalMeters: 80_000,
            longitudinalMeters: 80_000
        ))
    }
}
