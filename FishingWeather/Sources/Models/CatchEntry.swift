import Foundation

/// Provenance for condition values attached to a catch.
///
/// Raw condition fields from older app versions remain decodable so a later
/// transaction never destroys the user's legacy JSON. New fields are captured
/// only while an NWS snapshot is valid; after capture, this source metadata is
/// durable attribution rather than a second forecast-validity check.
struct CatchConditionSource: Codable, Equatable, Sendable {
    let providerKind: WeatherProviderKind
    let expiresAt: Date

    init(providerKind: WeatherProviderKind, expiresAt: Date) {
        self.providerKind = providerKind
        self.expiresAt = expiresAt
    }

    init?(weatherProvenance: WeatherProvenance, at date: Date) {
        guard weatherProvenance.isValid(at: date),
              let attribution = weatherProvenance.providerAttribution,
              attribution.providerKind == .nationalWeatherService,
              attribution.hasRequiredSecureMetadata
        else { return nil }
        self.init(
            providerKind: .nationalWeatherService,
            expiresAt: weatherProvenance.expiresAt
        )
    }

    var isDurablyAttributable: Bool {
        providerKind == .nationalWeatherService
            && expiresAt.timeIntervalSinceReferenceDate.isFinite
    }

    func isEligibleForNewPersistence(at date: Date) -> Bool {
        isDurablyAttributable
            && date.timeIntervalSinceReferenceDate.isFinite
            && date < expiresAt
    }
}

enum CatchTideProviderKind: String, Codable, Equatable, Sendable {
    case noaaCOOPS
}

/// Tide movement is NOAA CO-OPS data, not NWS weather. Keep its source identity
/// separate so a catch never implies NWS supplied a tide prediction.
struct CatchTideSource: Codable, Equatable, Sendable {
    let providerKind: CatchTideProviderKind
    let stationID: String

    init(
        providerKind: CatchTideProviderKind = .noaaCOOPS,
        stationID: String
    ) {
        self.providerKind = providerKind
        self.stationID = stationID
    }

    var isDurablyAttributable: Bool {
        providerKind == .noaaCOOPS
            && !stationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum CatchAstronomyProviderKind: String, Codable, Equatable, Sendable {
    case onDeviceCalculation
}

/// NWS does not supply BiteCast's moon phase. This separate identity records
/// that LocalAstronomyProvider calculated it on device.
struct CatchAstronomySource: Codable, Equatable, Sendable {
    let providerKind: CatchAstronomyProviderKind
    let algorithmVersion: Int

    init(
        providerKind: CatchAstronomyProviderKind = .onDeviceCalculation,
        algorithmVersion: Int = 1
    ) {
        self.providerKind = providerKind
        self.algorithmVersion = algorithmVersion
    }

    var isDurablyAttributable: Bool {
        providerKind == .onDeviceCalculation && algorithmVersion == 1
    }
}

/// A logged catch, with an automatic snapshot of the conditions when it happened.
struct CatchEntry: Identifiable, Codable, Equatable, Sendable {
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
    var dewPointF: Double?
    /// Wind speed (mph) when the catch was logged. Optional — older logs and
    /// catches saved without live weather have none. Feeds wind personalization.
    var windMph: Double?
    /// Tide movement when logged — "Rising", "Falling", or "Slack" — captured
    /// only at coastal spots with loaded tide data. Feeds tide personalization.
    var tidePhase: String?
    /// Absent on legacy catches and on all Apple Weather-origin catches.
    /// The raw fields above remain for backward-compatible decoding only.
    var conditionSource: CatchConditionSource?
    /// Explicit NOAA attribution for `tidePhase`; never inferred from weather.
    var tideSource: CatchTideSource?
    /// Explicit on-device attribution for `moonPhase`; never inferred as NWS.
    var astronomySource: CatchAstronomySource?

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
        dewPointF: Double? = nil,
        windMph: Double? = nil,
        tidePhase: String? = nil,
        conditionSource: CatchConditionSource? = nil,
        tideSource: CatchTideSource? = nil,
        astronomySource: CatchAstronomySource? = nil,
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
        self.dewPointF = dewPointF
        self.windMph = windMph
        self.tidePhase = tidePhase
        self.conditionSource = conditionSource
        self.tideSource = tideSource
        self.astronomySource = astronomySource
        self.photoFilename = photoFilename
    }

    var attributedPressureTendency: String? {
        hasDurableWeatherAttribution ? pressureTendency : nil
    }

    var attributedMoonPhase: String? {
        astronomySource?.isDurablyAttributable == true ? moonPhase : nil
    }

    var attributedAirTempF: Double? {
        hasDurableWeatherAttribution ? airTempF : nil
    }

    var attributedDewPointF: Double? {
        hasDurableWeatherAttribution ? dewPointF : nil
    }

    var attributedWindMph: Double? {
        hasDurableWeatherAttribution ? windMph : nil
    }

    var attributedTidePhase: String? {
        tideSource?.isDurablyAttributable == true ? tidePhase : nil
    }

    /// Enforced at the repository boundary for every newly added catch, so a
    /// future call site cannot accidentally make Apple or unattributed weather
    /// durable. Existing decoded entries are never passed through this method.
    func preparedForNewPersistence(at date: Date) -> Self {
        var copy = self
        if conditionSource?.isEligibleForNewPersistence(at: date) != true {
            copy.pressureTendency = nil
            copy.airTempF = nil
            copy.dewPointF = nil
            copy.windMph = nil
            copy.conditionSource = nil
        }
        if tideSource?.isDurablyAttributable != true {
            copy.tidePhase = nil
            copy.tideSource = nil
        }
        if astronomySource?.isDurablyAttributable != true {
            copy.moonPhase = nil
            copy.astronomySource = nil
        }
        return copy
    }

    private var hasDurableWeatherAttribution: Bool {
        conditionSource?.isDurablyAttributable == true
    }

    /// A one-line summary of size, e.g. "18 in · 3.2 lb".
    var sizeSummary: String? {
        var parts: [String] = []
        if let lengthInches { parts.append("\(lengthInches.formatted(.number.precision(.fractionLength(0...1)))) in") }
        if let weightPounds { parts.append("\(weightPounds.formatted(.number.precision(.fractionLength(0...1)))) lb") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
