import Foundation
import Testing
import UIKit
@testable import BiteCast

/// Persistence safety for the catch log: a corrupt or unreadable file must
/// never be silently discarded and then overwritten by the next save.
@MainActor
@Suite("CatchLog persistence")
struct CatchLogTests {
    private final class ProtectionLedger {
        private var requests: [URL: FileProtectionType] = [:]

        func record(url: URL, protection: FileProtectionType) {
            requests[url.standardizedFileURL] = protection
        }

        func protection(for url: URL) -> FileProtectionType? {
            requests[url.standardizedFileURL]
        }
    }

    private actor ThumbnailGate {
        private var started = false
        private var released = false

        func load(image: UIImage) async -> CatchLog.ThumbnailLoad {
            started = true
            while !released {
                await Task.yield()
            }
            return CatchLog.ThumbnailLoad(
                image: image,
                generatedData: image.jpegData(compressionQuality: 0.8)
            )
        }

        func waitUntilStarted() async {
            while !started {
                await Task.yield()
            }
        }

        func release() {
            released = true
        }
    }

    private final class FailurePlan {
        private var remaining: [CatchFileFailurePoint: Int] = [:]

        func failNext(_ points: CatchFileFailurePoint...) {
            for point in points {
                remaining[point, default: 0] += 1
            }
        }

        func inject(_ point: CatchFileFailurePoint) throws {
            guard let count = remaining[point], count > 0 else { return }
            remaining[point] = count - 1
            throw InjectedFailure(point: point)
        }
    }

    private struct InjectedFailure: Error {
        let point: CatchFileFailurePoint
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatchLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makePhoto() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        }
    }

    @Test
    func roundTripsEntriesThroughDisk() throws {
        let dir = try makeTempDirectory()
        let log = CatchLog(directory: dir)
        try log.add(CatchEntry(species: .bass, bait: "spinnerbait"), photo: nil)

        let reloaded = CatchLog(directory: dir)
        #expect(reloaded.entries.count == 1)
        #expect(reloaded.entries.first?.bait == "spinnerbait")
    }

    @Test("Legacy condition fields decode and survive later catch writes without becoming usable")
    func legacyConditionFieldsRemainCompatibleButUntrusted() throws {
        let dir = try makeTempDirectory()
        let legacy = CatchEntry(
            species: .bass,
            bait: "worm",
            pressureTendency: "Falling",
            moonPhase: "Full Moon",
            airTempF: 78,
            dewPointF: 69,
            windMph: 8,
            tidePhase: "Rising"
        )
        try JSONEncoder().encode([legacy]).write(
            to: dir.appendingPathComponent("catches.json")
        )

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let log = CatchLog(directory: dir)
        let decodedLegacy = try #require(log.entries.first)
        #expect(decodedLegacy.pressureTendency == "Falling")
        #expect(decodedLegacy.moonPhase == "Full Moon")
        #expect(decodedLegacy.airTempF == 78)
        #expect(decodedLegacy.dewPointF == 69)
        #expect(decodedLegacy.windMph == 8)
        #expect(decodedLegacy.tidePhase == "Rising")
        #expect(decodedLegacy.conditionSource == nil)
        #expect(decodedLegacy.attributedPressureTendency == nil)
        #expect(decodedLegacy.attributedMoonPhase == nil)
        #expect(decodedLegacy.attributedAirTempF == nil)
        #expect(decodedLegacy.attributedDewPointF == nil)
        #expect(decodedLegacy.attributedWindMph == nil)
        #expect(decodedLegacy.attributedTidePhase == nil)

        try log.add(CatchEntry(species: .crappie, bait: "jig"), photo: nil, now: now)
        let reloaded = CatchLog(directory: dir)
        let preserved = try #require(reloaded.entries.first { $0.id == legacy.id })
        #expect(preserved.pressureTendency == legacy.pressureTendency)
        #expect(preserved.moonPhase == legacy.moonPhase)
        #expect(preserved.airTempF == legacy.airTempF)
        #expect(preserved.dewPointF == legacy.dewPointF)
        #expect(preserved.windMph == legacy.windMph)
        #expect(preserved.tidePhase == legacy.tidePhase)

        let storedData = try Data(contentsOf: reloaded.storagePaths.metadataURL)
        let storedObjects = try #require(
            JSONSerialization.jsonObject(with: storedData) as? [[String: Any]]
        )
        let legacyObject = try #require(storedObjects.first {
            ($0["id"] as? String)?.lowercased() == legacy.id.uuidString.lowercased()
        })
        #expect(legacyObject["conditionSource"] == nil)
        #expect(legacyObject["pressureTendency"] as? String == "Falling")
        #expect(legacyObject["moonPhase"] as? String == "Full Moon")
        #expect(legacyObject["airTempF"] as? Double == 78)
        #expect(legacyObject["dewPointF"] as? Double == 69)
        #expect(legacyObject["windMph"] as? Double == 8)
        #expect(legacyObject["tidePhase"] as? String == "Rising")
    }

    @Test("Catch provenance is minted only from an unexpired attributed NWS snapshot")
    func catchSourceRequiresLiveAttributedNWSProvenance() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expiresAt = now.addingTimeInterval(900)
        let nws = WeatherProvenance(
            source: .nws,
            fetchedAt: now.addingTimeInterval(-60),
            isFallback: true,
            attribution: "National Weather Service",
            providerAttribution: .nationalWeatherService,
            expiresAt: expiresAt
        )
        let apple = WeatherProvenance(
            source: .weatherKit,
            fetchedAt: now.addingTimeInterval(-60),
            isFallback: false,
            attribution: "Apple Weather",
            providerAttribution: WeatherProviderAttribution(
                providerKind: .appleWeather,
                serviceName: "Apple Weather",
                legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
                combinedMarkLightURL: URL(string: "https://example.com/light.png"),
                combinedMarkDarkURL: URL(string: "https://example.com/dark.png"),
                legalText: nil
            ),
            expiresAt: expiresAt
        )

        let source = CatchConditionSource(
            weatherProvenance: nws,
            at: now
        )
        #expect(source == CatchConditionSource(
            providerKind: .nationalWeatherService,
            expiresAt: expiresAt
        ))
        #expect(source?.isEligibleForNewPersistence(at: now) == true)
        #expect(source?.isEligibleForNewPersistence(at: expiresAt) == false)
        #expect(source?.isDurablyAttributable == true)
        #expect(CatchConditionSource(weatherProvenance: nws, at: expiresAt) == nil)
        #expect(CatchConditionSource(weatherProvenance: apple, at: now) == nil)
    }

    @Test("Only unexpired NWS condition snapshots survive a new catch transaction")
    func newCatchConditionPersistenceRequiresValidNWSSource() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let future = now.addingTimeInterval(900)
        let values = CatchEntry(
            species: .redfish,
            bait: "paddletail",
            pressureTendency: "Steady",
            moonPhase: "New Moon",
            airTempF: 81,
            dewPointF: 73,
            windMph: 11
        )

        let cases: [(WeatherProviderKind?, Date?, Bool)] = [
            (.nationalWeatherService, future, true),
            (.nationalWeatherService, now, false),
            (
                .nationalWeatherService,
                Date(timeIntervalSinceReferenceDate: .infinity),
                false
            ),
            (.appleWeather, future, false),
            (nil, nil, false),
        ]

        for (providerKind, expiresAt, shouldPersist) in cases {
            let dir = try makeTempDirectory()
            let log = CatchLog(directory: dir)
            var entry = values
            if let providerKind, let expiresAt {
                entry.conditionSource = CatchConditionSource(
                    providerKind: providerKind,
                    expiresAt: expiresAt
                )
            }
            if shouldPersist {
                entry.astronomySource = CatchAstronomySource()
            }

            try log.add(entry, photo: nil, now: now)
            let saved = try #require(CatchLog(directory: dir).entries.first)

            if shouldPersist {
                #expect(saved.conditionSource?.providerKind == .nationalWeatherService)
                #expect(saved.conditionSource?.expiresAt == future)
                #expect(saved.attributedPressureTendency == "Steady")
                #expect(saved.attributedMoonPhase == "New Moon")
                #expect(saved.astronomySource == CatchAstronomySource())
                #expect(saved.attributedAirTempF == 81)
                #expect(saved.attributedDewPointF == 73)
                #expect(saved.attributedWindMph == 11)
                // Provider expiry gates capture, not durable historical use.
                #expect(saved.conditionSource?.isEligibleForNewPersistence(
                    at: future
                ) == false)
                #expect(saved.attributedPressureTendency == "Steady")
            } else {
                #expect(saved.conditionSource == nil)
                #expect(saved.pressureTendency == nil)
                #expect(saved.moonPhase == nil)
                #expect(saved.airTempF == nil)
                #expect(saved.dewPointF == nil)
                #expect(saved.windMph == nil)
            }
        }
    }

    @Test("NOAA tide provenance is durable and never implied to be NWS")
    func noaaTideSourceIsIndependent() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let directory = try makeTempDirectory()
        let log = CatchLog(directory: directory)
        let tideSource = CatchTideSource(stationID: "8720218")
        let entry = CatchEntry(
            species: .redfish,
            bait: "paddletail",
            tidePhase: "Falling",
            tideSource: tideSource
        )

        try log.add(entry, photo: nil, now: now)
        let saved = try #require(CatchLog(directory: directory).entries.first)

        #expect(saved.conditionSource == nil)
        #expect(saved.tideSource == tideSource)
        #expect(saved.attributedTidePhase == "Falling")

        let untrusted = CatchLog(directory: try makeTempDirectory())
        try untrusted.add(CatchEntry(
            species: .redfish,
            bait: "shrimp",
            tidePhase: "Rising"
        ), photo: nil, now: now)
        #expect(untrusted.entries.first?.tidePhase == nil)
        #expect(untrusted.entries.first?.attributedTidePhase == nil)
    }

    @Test("On-device moon provenance is separate from NWS weather")
    func onDeviceAstronomySourceIsIndependent() throws {
        let directory = try makeTempDirectory()
        let log = CatchLog(directory: directory)
        let entry = CatchEntry(
            species: .bass,
            bait: "worm",
            moonPhase: "First Quarter",
            astronomySource: CatchAstronomySource()
        )

        try log.add(entry, photo: nil, now: .now)
        let saved = try #require(log.entries.first)
        #expect(saved.conditionSource == nil)
        #expect(saved.astronomySource == CatchAstronomySource())
        #expect(saved.attributedMoonPhase == "First Quarter")
    }

    @Test
    func corruptFileIsBackedUpBeforeAnythingOverwritesIt() throws {
        let dir = try makeTempDirectory()
        let corrupt = Data("{definitely not json".utf8)
        try corrupt.write(to: dir.appendingPathComponent("catches.json"))
        let protections = ProtectionLedger()

        let log = CatchLog(
            directory: dir,
            protectionRecorder: protections.record
        )
        #expect(log.entries.isEmpty)

        // The unreadable original must survive as a recovery file…
        let recovered = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("catches-recovered") }
        #expect(recovered.count == 1)
        #expect(try Data(contentsOf: try #require(recovered.first)) == corrupt)
        #expect(protections.protection(for: try #require(recovered.first)) == .complete)

        // …even after a new catch is saved over catches.json.
        try log.add(CatchEntry(species: .bass, bait: "worm"), photo: nil)
        #expect(try Data(contentsOf: try #require(recovered.first)) == corrupt)
        let reloaded = CatchLog(directory: dir)
        #expect(reloaded.entries.count == 1)
    }

    @Test
    func oneMalformedEntryDoesNotDiscardTheRest() throws {
        let dir = try makeTempDirectory()
        let good = CatchEntry(species: .crappie, bait: "jig")
        let goodData = try JSONEncoder().encode([good])
        var text = try #require(String(data: goodData, encoding: .utf8))
        text = String(text.dropLast()) + #",{"id":42}]"#
        try Data(text.utf8).write(to: dir.appendingPathComponent("catches.json"))

        let log = CatchLog(directory: dir)
        #expect(log.entries.count == 1)
        #expect(log.entries.first?.bait == "jig")
    }

    @Test
    func removingAnEntryPersists() throws {
        let dir = try makeTempDirectory()
        let log = CatchLog(directory: dir)
        let entry = CatchEntry(species: .bass, bait: "chatterbait")
        try log.add(entry, photo: nil)
        try log.remove(entry)

        let reloaded = CatchLog(directory: dir)
        #expect(reloaded.entries.isEmpty)
    }

    @Test
    func failedSaveAndDeleteUIStateRetainsPresentationAndShowsAlerts() throws {
        let saveDirectory = try makeTempDirectory()
        let saveFailures = FailurePlan()
        saveFailures.failNext(.replaceMetadata)
        let saveLog = CatchLog(
            directory: saveDirectory,
            failureInjector: saveFailures.inject
        )
        var saveFormIsPresented = true

        let saveState = CatchOperationUIState.perform {
            try saveLog.add(
                CatchEntry(species: .bass, bait: "spinnerbait"),
                photo: makePhoto()
            )
        }
        if saveState.committed {
            saveFormIsPresented = false
        }

        #expect(!saveState.committed)
        #expect(saveFormIsPresented)
        #expect(saveLog.entries.isEmpty)
        #expect(saveState.alertMessage == saveLog.lastErrorMessage)
        #expect(saveState.alertMessage?.isEmpty == false)

        let deleteDirectory = try makeTempDirectory()
        let deleteFailures = FailurePlan()
        let deleteLog = CatchLog(
            directory: deleteDirectory,
            failureInjector: deleteFailures.inject
        )
        let entry = CatchEntry(species: .crappie, bait: "jig")
        try deleteLog.add(entry, photo: nil)
        let saved = try #require(deleteLog.entries.first)
        deleteFailures.failNext(.replaceMetadata)

        let deleteState = CatchOperationUIState.perform {
            try deleteLog.remove(saved)
        }

        #expect(!deleteState.committed)
        #expect(deleteLog.entries == [saved])
        #expect(deleteState.alertMessage == deleteLog.lastErrorMessage)
        #expect(deleteState.alertMessage?.isEmpty == false)
    }

    @Test
    func maliciousLegacyPhotoPathsCannotEscapePrivatePhotoStorage() throws {
        let dir = try makeTempDirectory()
        let absoluteSentinelURL = dir.appendingPathComponent("absolute-sentinel.jpg")
        let entries = [
            CatchEntry(
                species: .bass,
                bait: "worm",
                photoFilename: "../outside-sentinel.jpg"
            ),
            CatchEntry(
                species: .bluegill,
                bait: "beetle spin",
                photoFilename: absoluteSentinelURL.path
            ),
            CatchEntry(
                species: .catfish,
                bait: "cut bait",
                photoFilename: "nested/nested-sentinel.jpg"
            ),
            CatchEntry(species: .crappie, bait: "jig", photoFilename: "."),
            CatchEntry(species: .snook, bait: "pinfish", photoFilename: ".."),
        ]
        try JSONEncoder().encode(entries).write(
            to: dir.appendingPathComponent("catches.json")
        )

        let log = CatchLog(directory: dir)
        #expect(Set(log.entries.map(\.id)) == Set(entries.map(\.id)))

        let sentinel = Data("must-not-be-removed".utf8)
        let outsideSentinelURL = log.storagePaths.rootDirectory
            .appendingPathComponent("outside-sentinel.jpg")
        let nestedDirectory = log.storagePaths.photosDirectory
            .appendingPathComponent("nested", isDirectory: true)
        let nestedSentinelURL = nestedDirectory
            .appendingPathComponent("nested-sentinel.jpg")
        try FileManager.default.createDirectory(
            at: nestedDirectory,
            withIntermediateDirectories: true
        )
        for url in [absoluteSentinelURL, outsideSentinelURL, nestedSentinelURL] {
            try sentinel.write(to: url)
        }

        for entry in entries {
            try log.remove(entry)
        }

        #expect(log.entries.isEmpty)
        for url in [absoluteSentinelURL, outsideSentinelURL, nestedSentinelURL] {
            #expect(try Data(contentsOf: url) == sentinel)
        }
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(
            atPath: log.storagePaths.rootDirectory.path,
            isDirectory: &isDirectory
        ))
        #expect(isDirectory.boolValue)
        isDirectory = false
        #expect(FileManager.default.fileExists(
            atPath: log.storagePaths.photosDirectory.path,
            isDirectory: &isDirectory
        ))
        #expect(isDirectory.boolValue)
        isDirectory = false
        #expect(FileManager.default.fileExists(
            atPath: nestedDirectory.path,
            isDirectory: &isDirectory
        ))
        #expect(isDirectory.boolValue)
    }

    @Test
    func failedPhotoStageLeavesTheOldLogAndDiskUnchanged() throws {
        let dir = try makeTempDirectory()
        let failures = FailurePlan()
        failures.failNext(.stagePhoto)
        let log = CatchLog(directory: dir, failureInjector: failures.inject)

        #expect(throws: (any Error).self) {
            try log.add(CatchEntry(species: .bass, bait: "worm"), photo: makePhoto())
        }

        #expect(log.entries.isEmpty)
        #expect(log.lastErrorMessage != nil)
        #expect(try FileManager.default.contentsOfDirectory(
            at: log.storagePaths.photosDirectory,
            includingPropertiesForKeys: nil
        ).isEmpty)
        #expect(CatchLog(directory: dir).entries.isEmpty)

        // The UI observes this error state; a successful retry clears it.
        try log.add(CatchEntry(species: .bass, bait: "worm"), photo: nil)
        #expect(log.lastErrorMessage == nil)
        #expect(log.entries.count == 1)
    }

    @Test
    func failedJournalWriteCleansStagedPhoto() throws {
        let dir = try makeTempDirectory()
        let failures = FailurePlan()
        failures.failNext(.writeJournal)
        let log = CatchLog(directory: dir, failureInjector: failures.inject)

        #expect(throws: (any Error).self) {
            try log.add(CatchEntry(species: .crappie, bait: "jig"), photo: makePhoto())
        }

        #expect(log.entries.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(
            at: log.storagePaths.transactionsDirectory,
            includingPropertiesForKeys: nil
        ).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: log.storagePaths.journalURL.path))
    }

    @Test
    func failedMetadataReplaceRollsBackTheNewPhotoAndEntry() throws {
        let dir = try makeTempDirectory()
        let failures = FailurePlan()
        failures.failNext(.replaceMetadata)
        let log = CatchLog(directory: dir, failureInjector: failures.inject)

        #expect(throws: (any Error).self) {
            try log.add(CatchEntry(species: .bluegill, bait: "beetle spin"), photo: makePhoto())
        }

        #expect(log.entries.isEmpty)
        #expect(CatchLog(directory: dir).entries.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(
            at: log.storagePaths.photosDirectory,
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    @Test
    func failedCommitDirectorySyncCannotAcknowledgeOrPartiallyKeepAnAdd() throws {
        let dir = try makeTempDirectory()
        let failures = FailurePlan()
        let log = CatchLog(directory: dir, failureInjector: failures.inject)
        failures.failNext(.syncJournalCommit)

        #expect(throws: (any Error).self) {
            try log.add(
                CatchEntry(species: .snook, bait: "pinfish"),
                photo: makePhoto()
            )
        }

        #expect(log.entries.isEmpty)
        let reloaded = CatchLog(directory: dir)
        #expect(reloaded.entries.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(
            at: reloaded.storagePaths.photosDirectory,
            includingPropertiesForKeys: nil
        ).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: reloaded.storagePaths.journalURL.path))
    }

    @Test
    func addRejectsAPreexistingPhotoCollisionWithoutDeletingEitherFile() throws {
        let dir = try makeTempDirectory()
        let log = CatchLog(directory: dir)
        let entry = CatchEntry(
            id: UUID(uuidString: "2F4369AD-5123-40D8-A257-75A0B94F6034")!,
            species: .bass,
            bait: "worm"
        )
        let filename = "\(entry.id.uuidString.lowercased()).jpg"
        let originalPhoto = Data("preexisting-photo".utf8)
        let originalThumbnail = Data("preexisting-thumbnail".utf8)
        try originalPhoto.write(to: log.storagePaths.photoURL(for: filename))
        try originalThumbnail.write(to: log.storagePaths.thumbnailURL(for: filename))

        #expect(throws: CatchRepositoryError.self) {
            try log.add(entry, photo: makePhoto())
        }

        #expect(log.entries.isEmpty)
        #expect(try Data(contentsOf: log.storagePaths.photoURL(for: filename)) == originalPhoto)
        #expect(
            try Data(contentsOf: log.storagePaths.thumbnailURL(for: filename))
                == originalThumbnail
        )
        #expect(!FileManager.default.fileExists(atPath: log.storagePaths.journalURL.path))
    }

    @Test
    func installRaceDoesNotTurnAnExternalCollisionIntoAnOrphan() throws {
        let dir = try makeTempDirectory()
        let entry = CatchEntry(
            id: UUID(uuidString: "4BC5240B-3725-43A0-8970-6AC2D8BFE489")!,
            species: .crappie,
            bait: "jig"
        )
        let paths = CatchRepository.Paths(baseDirectory: dir)
        let filename = "\(entry.id.uuidString.lowercased()).jpg"
        let racedPhoto = Data("raced-photo".utf8)
        var insertedCollision = false
        let log = CatchLog(directory: dir, failureInjector: { point in
            guard point == .installPhoto, !insertedCollision else { return }
            insertedCollision = true
            try racedPhoto.write(to: paths.photoURL(for: filename))
        })

        #expect(throws: (any Error).self) {
            try log.add(entry, photo: makePhoto())
        }

        #expect(insertedCollision)
        #expect(log.entries.isEmpty)
        #expect(try Data(contentsOf: paths.photoURL(for: filename)) == racedPhoto)
        #expect(!FileManager.default.fileExists(atPath: paths.journalURL.path))
        #expect(try FileManager.default.contentsOfDirectory(
            at: paths.transactionsDirectory,
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    @Test
    func failedRemoveRestoresMetadataPhotoAndThumbnail() throws {
        let dir = try makeTempDirectory()
        let failures = FailurePlan()
        let log = CatchLog(directory: dir, failureInjector: failures.inject)
        let entry = CatchEntry(species: .redfish, bait: "paddletail")
        try log.add(entry, photo: makePhoto())
        let saved = try #require(log.entries.first)
        failures.failNext(.removeThumbnail)

        #expect(throws: (any Error).self) {
            try log.remove(saved)
        }

        #expect(log.entries == [saved])
        #expect(log.lastErrorMessage != nil)
        #expect(log.photo(for: saved) != nil)
        let reloaded = CatchLog(directory: dir)
        #expect(reloaded.entries == [saved])
        #expect(reloaded.photo(for: saved) != nil)
        let filename = try #require(saved.photoFilename)
        #expect(FileManager.default.fileExists(
            atPath: reloaded.storagePaths.thumbnailURL(for: filename).path
        ))

        try log.remove(saved)
        #expect(log.entries.isEmpty)
        #expect(log.lastErrorMessage == nil)
    }

    @Test
    func launchRecoveryRestoresAnInterruptedRemove() throws {
        let dir = try makeTempDirectory()
        let failures = FailurePlan()
        let log = CatchLog(directory: dir, failureInjector: failures.inject)
        try log.add(
            CatchEntry(species: .speckledTrout, bait: "popping cork"),
            photo: makePhoto()
        )
        let saved = try #require(log.entries.first)
        failures.failNext(.removeThumbnail, .recoveryMetadata)

        #expect(throws: (any Error).self) {
            try log.remove(saved)
        }
        #expect(log.entries == [saved])
        #expect(FileManager.default.fileExists(atPath: log.storagePaths.journalURL.path))

        let recovered = CatchLog(directory: dir)

        #expect(recovered.lastErrorMessage == nil)
        #expect(recovered.entries == [saved])
        #expect(recovered.photo(for: saved) != nil)
        let filename = try #require(saved.photoFilename)
        #expect(FileManager.default.fileExists(
            atPath: recovered.storagePaths.thumbnailURL(for: filename).path
        ))
        #expect(!FileManager.default.fileExists(atPath: recovered.storagePaths.journalURL.path))
    }

    @Test
    func thumbnailFinishingAfterRemoveCannotRecreateAnOrphan() async throws {
        let dir = try makeTempDirectory()
        let gate = ThumbnailGate()
        let staleImage = makePhoto()
        let log = CatchLog(directory: dir, thumbnailLoader: { _, _, _ in
            await gate.load(image: staleImage)
        })
        try log.add(
            CatchEntry(species: .bass, bait: "spinnerbait"),
            photo: makePhoto()
        )
        let saved = try #require(log.entries.first)
        let pending = Task { await log.thumbnail(for: saved) }
        await gate.waitUntilStarted()

        try log.remove(saved)
        await gate.release()
        let result = await pending.value

        #expect(result == nil)
        let filename = try #require(saved.photoFilename)
        #expect(!FileManager.default.fileExists(
            atPath: log.storagePaths.thumbnailURL(for: filename).path
        ))
    }

    @Test
    func launchRecoveryRollsBackAnInterruptedAddAndOnlyItsProvenFiles() throws {
        let dir = try makeTempDirectory()
        let failures = FailurePlan()
        let protections = ProtectionLedger()
        failures.failNext(.replaceMetadata, .recoveryMetadata)
        let log = CatchLog(
            directory: dir,
            protectionRecorder: protections.record,
            failureInjector: failures.inject
        )

        #expect(throws: (any Error).self) {
            try log.add(CatchEntry(species: .catfish, bait: "cut bait"), photo: makePhoto())
        }
        #expect(FileManager.default.fileExists(atPath: log.storagePaths.journalURL.path))
        #expect(protections.protection(for: log.storagePaths.journalURL) == .complete)

        let unrelated = log.storagePaths.photosDirectory.appendingPathComponent("user-kept.jpg")
        try Data("unrelated".utf8).write(to: unrelated)
        let recovered = CatchLog(directory: dir)

        #expect(recovered.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: recovered.storagePaths.journalURL.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        let photoNames = try FileManager.default.contentsOfDirectory(
            at: recovered.storagePaths.photosDirectory,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent)
        #expect(photoNames == ["user-kept.jpg"])
    }

    @Test
    func legacyFilesMoveIntoProtectedCatchStorage() throws {
        let dir = try makeTempDirectory()
        let filename = "legacy.jpg"
        let entry = CatchEntry(
            species: .flounder,
            bait: "mud minnow",
            photoFilename: filename
        )
        try JSONEncoder().encode([entry]).write(
            to: dir.appendingPathComponent("catches.json")
        )
        let legacyPhotos = dir.appendingPathComponent("CatchPhotos", isDirectory: true)
        try FileManager.default.createDirectory(
            at: legacyPhotos,
            withIntermediateDirectories: true
        )
        try makePhoto().jpegData(compressionQuality: 0.8)?.write(
            to: legacyPhotos.appendingPathComponent(filename)
        )
        try makePhoto().jpegData(compressionQuality: 0.8)?.write(
            to: legacyPhotos.appendingPathComponent("thumb-" + filename)
        )

        let protections = ProtectionLedger()
        let log = CatchLog(
            directory: dir,
            protectionRecorder: protections.record
        )

        #expect(log.entries == [entry])
        #expect(log.photo(for: entry) != nil)
        for url in [
            log.storagePaths.rootDirectory,
            log.storagePaths.metadataURL,
            log.storagePaths.photosDirectory,
            log.storagePaths.photoURL(for: filename),
            log.storagePaths.thumbnailURL(for: filename),
            log.storagePaths.transactionsDirectory,
        ] {
            #expect(
                protections.protection(for: url) == .complete,
                "Expected a complete-protection request for \(url.lastPathComponent)"
            )
        }
        #expect(!FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("catches.json").path
        ))
    }

    @Test
    func interruptedProtectionMigrationIsVisibleAndRetriedWithoutDataLoss() throws {
        let dir = try makeTempDirectory()
        let entry = CatchEntry(species: .pompano, bait: "sand flea")
        try JSONEncoder().encode([entry]).write(
            to: dir.appendingPathComponent("catches.json")
        )
        let failures = FailurePlan()
        let protections = ProtectionLedger()
        failures.failNext(.migrateProtection)

        let interrupted = CatchLog(
            directory: dir,
            protectionRecorder: protections.record,
            failureInjector: failures.inject
        )

        #expect(interrupted.entries == [entry])
        #expect(interrupted.lastErrorMessage != nil)

        let recovered = CatchLog(
            directory: dir,
            protectionRecorder: protections.record
        )
        #expect(recovered.entries == [entry])
        #expect(recovered.lastErrorMessage == nil)
        #expect(protections.protection(for: recovered.storagePaths.metadataURL) == .complete)
    }
}
