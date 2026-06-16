import Foundation

/// A logged catch, with an automatic snapshot of the conditions when it happened.
struct CatchEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var species: Species
    var bait: String
    var lengthInches: Double?
    var weightPounds: Double?
    var notes: String

    // Where
    var latitude: Double?
    var longitude: Double?
    var spotName: String?

    // Conditions snapshot
    var pressureTendency: String?
    var moonPhase: String?
    var airTempF: Double?

    // Photo, stored on disk by filename (not in the JSON).
    var photoFilename: String?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        species: Species,
        bait: String,
        lengthInches: Double? = nil,
        weightPounds: Double? = nil,
        notes: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        spotName: String? = nil,
        pressureTendency: String? = nil,
        moonPhase: String? = nil,
        airTempF: Double? = nil,
        photoFilename: String? = nil
    ) {
        self.id = id
        self.date = date
        self.species = species
        self.bait = bait
        self.lengthInches = lengthInches
        self.weightPounds = weightPounds
        self.notes = notes
        self.latitude = latitude
        self.longitude = longitude
        self.spotName = spotName
        self.pressureTendency = pressureTendency
        self.moonPhase = moonPhase
        self.airTempF = airTempF
        self.photoFilename = photoFilename
    }

    /// A one-line summary of size, e.g. "18 in · 3.2 lb".
    var sizeSummary: String? {
        var parts: [String] = []
        if let lengthInches { parts.append("\(lengthInches.formatted(.number.precision(.fractionLength(0...1)))) in") }
        if let weightPounds { parts.append("\(weightPounds.formatted(.number.precision(.fractionLength(0...1)))) lb") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
