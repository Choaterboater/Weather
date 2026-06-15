import SwiftUI

/// The species the angler is focusing on. `all` means no specific focus.
/// Persisted via `@AppStorage`, so the raw values are a stable storage contract.
enum Species: String, CaseIterable, Identifiable {
    case all
    case bass
    case crappie
    case catfish
    case bluegill

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: "All"
        case .bass: "Bass"
        case .crappie: "Crappie"
        case .catfish: "Catfish"
        case .bluegill: "Bluegill"
        }
    }

    var tint: Color {
        switch self {
        case .all: .teal
        case .bass: .green
        case .crappie: .indigo
        case .catfish: .brown
        case .bluegill: .orange
        }
    }

    /// How to name the focus to the model.
    var promptName: String {
        self == .all ? "freshwater fish (no specific species)" : displayName.lowercased()
    }

    /// A simple, static where-to-focus note. Deterministic guidance (not AI) —
    /// the Phase 4 bait engine produces the real, conditions-aware advice.
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
        }
    }
}
