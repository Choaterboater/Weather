import SwiftUI

/// The species the angler is focusing on. `all` means no specific focus.
/// Persisted via `@AppStorage`, so the raw values are a stable storage contract —
/// existing case raw values must not change.
enum Species: String, CaseIterable, Identifiable, Codable {
    case all

    // Freshwater
    case bass
    case crappie
    case catfish
    case bluegill

    // Saltwater (Gulf / South Atlantic focus to match curated regions)
    case redfish
    case speckledTrout
    case pompano
    case flounder
    case sheepshead
    case snook
    case mangroveSnapper

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: "All"
        case .bass: "Bass"
        case .crappie: "Crappie"
        case .catfish: "Catfish"
        case .bluegill: "Bluegill"
        case .redfish: "Redfish"
        case .speckledTrout: "Speckled Trout"
        case .pompano: "Pompano"
        case .flounder: "Flounder"
        case .sheepshead: "Sheepshead"
        case .snook: "Snook"
        case .mangroveSnapper: "Mangrove Snapper"
        }
    }

    var scientificName: String? {
        switch self {
        case .all: nil
        case .bass: "Micropterus salmoides"
        case .crappie: "Pomoxis spp."
        case .catfish: "Ictalurus spp."
        case .bluegill: "Lepomis macrochirus"
        case .redfish: "Sciaenops ocellatus"
        case .speckledTrout: "Cynoscion nebulosus"
        case .pompano: "Trachinotus carolinus"
        case .flounder: "Paralichthys spp."
        case .sheepshead: "Archosargus probatocephalus"
        case .snook: "Centropomus undecimalis"
        case .mangroveSnapper: "Lutjanus griseus"
        }
    }

    /// `nil` for `.all`; otherwise the water type this species lives in.
    var waterType: WaterType? {
        switch self {
        case .all: nil
        case .bass, .crappie, .catfish, .bluegill: .freshwater
        case .redfish, .speckledTrout, .pompano, .flounder,
             .sheepshead, .snook, .mangroveSnapper: .saltwater
        }
    }

    var tint: Color {
        switch self {
        case .all: .teal
        case .bass: .green
        case .crappie: .indigo
        case .catfish: .brown
        case .bluegill: .orange
        case .redfish: .red
        case .speckledTrout: Color(red: 0.6, green: 0.4, blue: 0.7)
        case .pompano: .yellow
        case .flounder: Color(red: 0.55, green: 0.45, blue: 0.3)
        case .sheepshead: .gray
        case .snook: Color(red: 0.2, green: 0.5, blue: 0.6)
        case .mangroveSnapper: Color(red: 0.4, green: 0.25, blue: 0.2)
        }
    }

    /// How to name the focus to the model.
    var promptName: String {
        switch self {
        case .all: "fish (no specific species)"
        default: displayName.lowercased()
        }
    }

    /// A simple, static where-to-focus note. Deterministic guidance (not AI) —
    /// the bait engine produces the real, conditions-aware advice.
    var focusNote: String {
        switch self {
        case .all:
            "Pick a species above for focused guidance."
        case .bass:
            "Work structure and cover — points, weed edges, and laydowns."
        case .crappie:
            "Look for suspended fish near brush and docks; lighter line, small jigs."
        case .catfish:
            "Fish the bottom near channels and holes; scent baits shine after dark."
        case .bluegill:
            "Hit shallow flats and beds with tiny baits under a float."
        case .redfish:
            "Sight-fish flats and oyster bars on moving water; cut bait or gold spoons."
        case .speckledTrout:
            "Grass flats at first light and dusk; soft plastics under a popping cork."
        case .pompano:
            "Surf troughs on a rising tide; sand fleas or pompano jigs."
        case .flounder:
            "Sandy bottoms near structure; slow-drag a jig with a minnow or Gulp."
        case .sheepshead:
            "Bridge pilings, docks, jetties — fiddler crabs or shrimp on a tight line."
        case .snook:
            "Mangroves, dock lights, and inlets on a moving tide; live pinfish or twitchbaits."
        case .mangroveSnapper:
            "Structure and reefs; light fluorocarbon, live shrimp or small pilchards."
        }
    }

    /// Whether this species is available to pick given the active spot's water type.
    /// `.all` is always available; species match their own water type.
    func isAvailable(for waterType: WaterType?) -> Bool {
        guard let waterType else { return true }
        guard let mine = self.waterType else { return true }
        return mine == waterType
    }

    /// Photo credit line for the bundled Asset Catalog image. Source photos
    /// are Creative Commons-licensed from iNaturalist's taxon pages.
    var photoCredit: String? {
        switch self {
        case .all: nil
        case .bass: "© Phil's 1stPix · CC BY-NC-SA · iNaturalist"
        case .crappie: "Eric Engbretson, USFWS · public domain · iNaturalist"
        case .catfish: "© Mitchel Buckner · CC BY-NC · iNaturalist"
        case .bluegill: "© Kristiina Hurme · CC BY · iNaturalist"
        case .redfish: "© Jacob Jones · CC BY-NC · iNaturalist"
        case .speckledTrout: "© Quinn · CC BY · iNaturalist"
        case .pompano: "© Jacob Jones · CC BY-NC · iNaturalist"
        case .flounder: "© Kyran Leeker · iNaturalist"
        case .sheepshead: "© Pauline Walsh Jacobson · CC BY · iNaturalist"
        case .snook: "© Kevin Bryant · CC BY-NC-SA · iNaturalist"
        case .mangroveSnapper: "© Frank Krasovec · CC BY-NC · iNaturalist"
        }
    }
}
