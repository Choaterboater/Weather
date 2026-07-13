import Darwin
import Foundation

/// Owns the on-disk representation of private catch history.
///
/// All mutations use a protected rollback journal. Journal removal is the only
/// commit point, so launch recovery can conservatively restore an interrupted
/// operation without guessing which files are safe to remove.
@MainActor
final class CatchRepository {
    typealias FailureInjector = (CatchFileFailurePoint) throws -> Void
    typealias ProtectionRecorder = (URL, FileProtectionType) -> Void

    struct Paths: Equatable, Sendable {
        let baseDirectory: URL
        let rootDirectory: URL
        let metadataURL: URL
        let photosDirectory: URL
        let transactionsDirectory: URL
        let journalURL: URL
        let legacyMetadataURL: URL
        let legacyPhotosDirectory: URL

        init(baseDirectory: URL) {
            self.baseDirectory = baseDirectory
            rootDirectory = baseDirectory.appendingPathComponent("CatchData", isDirectory: true)
            metadataURL = rootDirectory.appendingPathComponent("catches.json")
            photosDirectory = rootDirectory.appendingPathComponent("Photos", isDirectory: true)
            transactionsDirectory = rootDirectory.appendingPathComponent("Transactions", isDirectory: true)
            journalURL = rootDirectory.appendingPathComponent("transaction.json")
            legacyMetadataURL = baseDirectory.appendingPathComponent("catches.json")
            legacyPhotosDirectory = baseDirectory.appendingPathComponent("CatchPhotos", isDirectory: true)
        }

        func photoURL(for filename: String) -> URL {
            photosDirectory.appendingPathComponent(filename)
        }

        func thumbnailURL(for filename: String) -> URL {
            photosDirectory.appendingPathComponent("thumb-" + filename)
        }

        func transactionDirectory(for transaction: CatchFileTransaction) -> URL {
            transactionsDirectory.appendingPathComponent(
                transaction.directoryName,
                isDirectory: true
            )
        }

        func stagedMetadataURL(for transaction: CatchFileTransaction) -> URL {
            transactionDirectory(for: transaction).appendingPathComponent("metadata-before.json")
        }

        func stagedPhotoURL(for transaction: CatchFileTransaction) -> URL {
            transactionDirectory(for: transaction).appendingPathComponent("photo.jpg")
        }

        func stagedThumbnailURL(for transaction: CatchFileTransaction) -> URL {
            transactionDirectory(for: transaction).appendingPathComponent("thumbnail.jpg")
        }
    }

    let paths: Paths

    private let fileManager: FileManager
    private let failureInjector: FailureInjector
    private let protectionRecorder: ProtectionRecorder
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseDirectory: URL,
        fileManager: FileManager = .default,
        protectionRecorder: @escaping ProtectionRecorder = { _, _ in },
        failureInjector: @escaping FailureInjector = { _ in }
    ) {
        paths = Paths(baseDirectory: baseDirectory)
        self.fileManager = fileManager
        self.protectionRecorder = protectionRecorder
        self.failureInjector = failureInjector
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func load() throws -> [CatchEntry] {
        try prepareStorage()
        try recoverInterruptedTransactionIfNeeded()
        try removeUnjournaledStaging()
        return try readEntries(backUpUnreadable: true)
    }

    /// Entries safe to show if launch recovery itself hits an I/O failure.
    /// A valid journal is authoritative: its snapshot is the last committed log.
    func bestEffortEntries() -> [CatchEntry] {
        if let data = try? Data(contentsOf: paths.journalURL),
           let transaction = try? decoder.decode(CatchFileTransaction.self, from: data),
           transaction.version == CatchFileTransaction.currentVersion {
            return transaction.originalEntries
        }
        return (try? readEntries(backUpUnreadable: false)) ?? []
    }

    func add(
        _ requestedEntry: CatchEntry,
        photoData: Data?,
        thumbnailData: Data?,
        to entries: [CatchEntry]
    ) throws -> [CatchEntry] {
        guard !entries.contains(where: { $0.id == requestedEntry.id }) else {
            throw CatchRepositoryError.duplicateIdentifier
        }
        try prepareForMutation()

        var entry = requestedEntry
        let filename = photoData == nil ? nil : "\(entry.id.uuidString.lowercased()).jpg"
        entry.photoFilename = filename
        if let filename {
            let photoURL = try validatedPhotoURL(filename)
            let thumbnailURL = try validatedThumbnailURL(filename)
            guard !fileManager.fileExists(atPath: photoURL.path),
                  !fileManager.fileExists(atPath: thumbnailURL.path) else {
                throw CatchRepositoryError.photoCollision
            }
        }
        let transaction = CatchFileTransaction(
            kind: .add,
            originalEntries: entries,
            metadataExisted: fileManager.fileExists(atPath: paths.metadataURL.path),
            photoFilename: filename,
            includesPhotoMutation: photoData != nil,
            includesThumbnailMutation: thumbnailData != nil,
            photoExisted: false,
            thumbnailExisted: false
        )
        let transactionDirectory = paths.transactionDirectory(for: transaction)
        var journalWasWritten = false

        do {
            try createProtectedDirectory(transactionDirectory)
            try stageCurrentMetadata(for: transaction)
            if let photoData {
                try failureInjector(.stagePhoto)
                try writeProtected(photoData, to: paths.stagedPhotoURL(for: transaction))
            }
            if let thumbnailData {
                try failureInjector(.stageThumbnail)
                try writeProtected(thumbnailData, to: paths.stagedThumbnailURL(for: transaction))
            }

            try failureInjector(.writeJournal)
            try writeProtected(encoder.encode(transaction), to: paths.journalURL)
            journalWasWritten = true

            if let filename {
                try failureInjector(.installPhoto)
                try moveProtected(
                    from: paths.stagedPhotoURL(for: transaction),
                    to: try validatedPhotoURL(filename)
                )
                if thumbnailData != nil {
                    try failureInjector(.installThumbnail)
                    try moveProtected(
                        from: paths.stagedThumbnailURL(for: transaction),
                        to: try validatedThumbnailURL(filename)
                    )
                }
            }

            var updated = entries
            updated.insert(entry, at: 0)
            try failureInjector(.replaceMetadata)
            try writeProtected(encoder.encode(updated), to: paths.metadataURL)

            try failureInjector(.removeJournal)
            try removeJournalAtCommitPoint(transaction)
            removeTransactionDirectoryBestEffort(transactionDirectory)
            return updated
        } catch {
            let originalError = error
            if journalWasWritten || fileManager.fileExists(atPath: paths.journalURL.path) {
                do {
                    try rollback(transaction)
                } catch {
                    throw CatchRepositoryError.recoveryRequired(
                        action: "save",
                        reason: error.localizedDescription
                    )
                }
            } else {
                removeTransactionDirectoryBestEffort(transactionDirectory)
            }
            throw CatchRepositoryError.operationFailed(
                action: "save",
                reason: originalError.localizedDescription
            )
        }
    }

    func remove(_ requestedEntry: CatchEntry, from entries: [CatchEntry]) throws -> [CatchEntry] {
        guard let existing = entries.first(where: { $0.id == requestedEntry.id }) else {
            return entries
        }
        try prepareForMutation()

        // Historical/corrupt filenames that are not a single local component
        // are never followed outside Photos. The entry can still be removed;
        // only a repository-managed photo is eligible for deletion.
        let filename = existing.photoFilename.flatMap { try? validatedFilename($0) }
        let photoURL = try filename.map(validatedPhotoURL)
        let thumbnailURL = try filename.map(validatedThumbnailURL)
        let photoExisted = photoURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
        let thumbnailExisted = thumbnailURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
        let transaction = CatchFileTransaction(
            kind: .remove,
            originalEntries: entries,
            metadataExisted: fileManager.fileExists(atPath: paths.metadataURL.path),
            photoFilename: filename,
            includesPhotoMutation: photoExisted,
            includesThumbnailMutation: thumbnailExisted,
            photoExisted: photoExisted,
            thumbnailExisted: thumbnailExisted
        )
        let transactionDirectory = paths.transactionDirectory(for: transaction)
        var journalWasWritten = false

        do {
            try createProtectedDirectory(transactionDirectory)
            try stageCurrentMetadata(for: transaction)
            if photoExisted, let photoURL {
                try failureInjector(.stagePhoto)
                try copyProtected(
                    from: photoURL,
                    to: paths.stagedPhotoURL(for: transaction)
                )
            }
            if thumbnailExisted, let thumbnailURL {
                try failureInjector(.stageThumbnail)
                try copyProtected(
                    from: thumbnailURL,
                    to: paths.stagedThumbnailURL(for: transaction)
                )
            }

            try failureInjector(.writeJournal)
            try writeProtected(encoder.encode(transaction), to: paths.journalURL)
            journalWasWritten = true

            let updated = entries.filter { $0.id != existing.id }
            try failureInjector(.replaceMetadata)
            try writeProtected(encoder.encode(updated), to: paths.metadataURL)

            if photoExisted, let photoURL {
                try failureInjector(.removePhoto)
                try removeDurably(photoURL)
            }
            if thumbnailExisted, let thumbnailURL {
                try failureInjector(.removeThumbnail)
                try removeDurably(thumbnailURL)
            }

            try failureInjector(.removeJournal)
            try removeJournalAtCommitPoint(transaction)
            removeTransactionDirectoryBestEffort(transactionDirectory)
            return updated
        } catch {
            let originalError = error
            if journalWasWritten || fileManager.fileExists(atPath: paths.journalURL.path) {
                do {
                    try rollback(transaction)
                } catch {
                    throw CatchRepositoryError.recoveryRequired(
                        action: "delete",
                        reason: error.localizedDescription
                    )
                }
            } else {
                removeTransactionDirectoryBestEffort(transactionDirectory)
            }
            throw CatchRepositoryError.operationFailed(
                action: "delete",
                reason: originalError.localizedDescription
            )
        }
    }

    func photoURL(for filename: String) throws -> URL {
        try validatedPhotoURL(filename)
    }

    func thumbnailURL(for filename: String) throws -> URL {
        try validatedThumbnailURL(filename)
    }

    func storeThumbnail(_ data: Data, filename: String) throws {
        try failureInjector(.writeThumbnail)
        try writeProtected(data, to: validatedThumbnailURL(filename))
    }

    // MARK: - Preparation and migration

    private func prepareStorage() throws {
        try failureInjector(.prepareDirectories)
        let baseExisted = fileManager.fileExists(atPath: paths.baseDirectory.path)
        try fileManager.createDirectory(
            at: paths.baseDirectory,
            withIntermediateDirectories: true
        )
        if !baseExisted {
            try synchronizeDirectory(paths.baseDirectory.deletingLastPathComponent())
        }
        try createProtectedDirectory(paths.rootDirectory)
        try createProtectedDirectory(paths.photosDirectory)
        try createProtectedDirectory(paths.transactionsDirectory)
        try migrateLegacyStorage()
        try failureInjector(.migrateProtection)
        try applyCompleteProtectionRecursively(to: paths.rootDirectory)
        try protectLegacyRecoveryFiles()
    }

    private func prepareForMutation() throws {
        try prepareStorage()
        try recoverInterruptedTransactionIfNeeded()
        try removeUnjournaledStaging()
    }

    private func migrateLegacyStorage() throws {
        let legacyMetadataExists = fileManager.fileExists(atPath: paths.legacyMetadataURL.path)
        let newMetadataExists = fileManager.fileExists(atPath: paths.metadataURL.path)

        if fileManager.fileExists(atPath: paths.legacyPhotosDirectory.path) {
            let legacyPhotoURLs = try fileManager.contentsOfDirectory(
                at: paths.legacyPhotosDirectory,
                includingPropertiesForKeys: nil
            )
            for source in legacyPhotoURLs {
                let destination = paths.photosDirectory.appendingPathComponent(
                    source.lastPathComponent
                )
                if !fileManager.fileExists(atPath: destination.path) {
                    // Upgrade before moving so an interruption never leaves a
                    // legacy user photo at a less-protected destination.
                    try applyCompleteProtection(to: source)
                    try synchronizeFile(at: source)
                    try moveProtected(from: source, to: destination)
                } else {
                    // A partial prior migration already installed this name.
                    // Keep the legacy copy protected rather than guessing that
                    // either user-owned file is safe to delete.
                    try applyCompleteProtection(to: source)
                }
            }
            if (try? fileManager.contentsOfDirectory(
                at: paths.legacyPhotosDirectory,
                includingPropertiesForKeys: nil
            ).isEmpty) == true {
                try? fileManager.removeItem(at: paths.legacyPhotosDirectory)
            } else {
                try applyCompleteProtection(to: paths.legacyPhotosDirectory)
            }
        }

        if legacyMetadataExists && !newMetadataExists {
            try applyCompleteProtection(to: paths.legacyMetadataURL)
            try synchronizeFile(at: paths.legacyMetadataURL)
            try moveProtected(from: paths.legacyMetadataURL, to: paths.metadataURL)
        } else if legacyMetadataExists {
            // Never discard a second historical log. It remains at the legacy
            // URL but is upgraded to complete protection.
            try applyCompleteProtection(to: paths.legacyMetadataURL)
        }
    }

    private func protectLegacyRecoveryFiles() throws {
        let children = try fileManager.contentsOfDirectory(
            at: paths.baseDirectory,
            includingPropertiesForKeys: nil
        )
        for child in children where child.lastPathComponent.hasPrefix("catches-recovered-") {
            try applyCompleteProtection(to: child)
        }
    }

    private func createProtectedDirectory(_ url: URL) throws {
        let existed = fileManager.fileExists(atPath: url.path)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try applyCompleteProtection(to: url)
        try synchronizeDirectory(url)
        if !existed {
            try synchronizeDirectory(url.deletingLastPathComponent())
        }
    }

    private func applyCompleteProtectionRecursively(to directory: URL) throws {
        try applyCompleteProtection(to: directory)
        for relativePath in try fileManager.subpathsOfDirectory(atPath: directory.path) {
            try applyCompleteProtection(
                to: directory.appendingPathComponent(relativePath)
            )
        }
    }

    private func applyCompleteProtection(to url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        // Simulator does not report a hardware protection class. Tests record
        // the exact production requests here; a signed physical-device gate
        // separately verifies the effective NSFileProtection value.
        protectionRecorder(url.standardizedFileURL, .complete)
    }

    // MARK: - Recovery

    private func recoverInterruptedTransactionIfNeeded() throws {
        guard fileManager.fileExists(atPath: paths.journalURL.path) else { return }
        try applyCompleteProtection(to: paths.journalURL)
        let data = try Data(contentsOf: paths.journalURL)
        guard let transaction = try? decoder.decode(CatchFileTransaction.self, from: data),
              transaction.version == CatchFileTransaction.currentVersion else {
            throw CatchRepositoryError.malformedJournal
        }
        try rollback(transaction)
    }

    private func rollback(_ transaction: CatchFileTransaction) throws {
        try failureInjector(.recoveryMetadata)
        try restoreOriginalMetadata(for: transaction)

        switch transaction.kind {
        case .add:
            if let filename = transaction.photoFilename {
                try failureInjector(.recoveryPhoto)
                let photoURL = try validatedPhotoURL(filename)
                let thumbnailURL = try validatedThumbnailURL(filename)
                let stagedPhotoStillExists = fileManager.fileExists(
                    atPath: paths.stagedPhotoURL(for: transaction).path
                )
                let stagedThumbnailStillExists = fileManager.fileExists(
                    atPath: paths.stagedThumbnailURL(for: transaction).path
                )
                // A missing stage proves this transaction installed the final
                // file. If the stage still exists, a destination collision is
                // pre-existing/external and must never be treated as an orphan.
                if transaction.includesPhotoMutation,
                   !stagedPhotoStillExists,
                   fileManager.fileExists(atPath: photoURL.path) {
                    try removeDurably(photoURL)
                }
                if transaction.includesThumbnailMutation,
                   !stagedThumbnailStillExists,
                   fileManager.fileExists(atPath: thumbnailURL.path) {
                    try removeDurably(thumbnailURL)
                }
            }
        case .remove:
            if let filename = transaction.photoFilename {
                try failureInjector(.recoveryPhoto)
                if transaction.photoExisted {
                    try restoreProtectedFile(
                        from: paths.stagedPhotoURL(for: transaction),
                        to: validatedPhotoURL(filename),
                        description: "the original catch photo"
                    )
                }
                if transaction.thumbnailExisted {
                    try restoreProtectedFile(
                        from: paths.stagedThumbnailURL(for: transaction),
                        to: validatedThumbnailURL(filename),
                        description: "the original catch thumbnail"
                    )
                }
            }
        }

        if fileManager.fileExists(atPath: paths.journalURL.path) {
            try removeDurably(paths.journalURL)
        }
        removeTransactionDirectoryBestEffort(paths.transactionDirectory(for: transaction))
    }

    private func restoreOriginalMetadata(for transaction: CatchFileTransaction) throws {
        if transaction.metadataExisted {
            let stagedURL = paths.stagedMetadataURL(for: transaction)
            guard fileManager.fileExists(atPath: stagedURL.path) else {
                throw CatchRepositoryError.missingRecoveryFile("the original catch log")
            }
            // Restore the exact original bytes. Re-encoding the decoded entries
            // could discard an individually malformed historical element.
            let data = try Data(contentsOf: stagedURL)
            try writeProtected(data, to: paths.metadataURL)
        } else if fileManager.fileExists(atPath: paths.metadataURL.path) {
            try removeDurably(paths.metadataURL)
        }
    }

    private func restoreProtectedFile(
        from stagedURL: URL,
        to destinationURL: URL,
        description: String
    ) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try applyCompleteProtection(to: destinationURL)
            return
        }
        guard fileManager.fileExists(atPath: stagedURL.path) else {
            throw CatchRepositoryError.missingRecoveryFile(description)
        }
        try copyProtected(from: stagedURL, to: destinationURL)
    }

    private func removeUnjournaledStaging() throws {
        guard !fileManager.fileExists(atPath: paths.journalURL.path) else { return }
        let children = try fileManager.contentsOfDirectory(
            at: paths.transactionsDirectory,
            includingPropertiesForKeys: nil
        )
        for child in children {
            // This directory contains only repository-created staging files.
            // Unlike the Photos directory, each child is therefore a provable
            // transaction orphan and safe to remove after the journal is gone.
            try removeDurably(child)
        }
    }

    // MARK: - Encoding and protected file operations

    private func stageCurrentMetadata(for transaction: CatchFileTransaction) throws {
        guard transaction.metadataExisted else { return }
        try failureInjector(.stageMetadata)
        let data = try Data(contentsOf: paths.metadataURL)
        try writeProtected(data, to: paths.stagedMetadataURL(for: transaction))
    }

    private func readEntries(backUpUnreadable: Bool) throws -> [CatchEntry] {
        guard fileManager.fileExists(atPath: paths.metadataURL.path) else { return [] }
        let data = try Data(contentsOf: paths.metadataURL)
        if let decoded = try? decoder.decode([CatchEntry].self, from: data) {
            return decoded
        }
        if backUpUnreadable {
            let backupURL = paths.baseDirectory.appendingPathComponent(
                "catches-recovered-\(UUID().uuidString.lowercased()).json"
            )
            try writeProtected(data, to: backupURL)
        }
        return (try? decoder.decode([FailableCatchEntry].self, from: data))?
            .compactMap(\.value) ?? []
    }

    private func writeProtected(_ data: Data, to url: URL) throws {
        var didWrite = false
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            didWrite = true
            try applyCompleteProtection(to: url)
            try synchronizeFile(at: url)
            try synchronizeDirectory(url.deletingLastPathComponent())
        } catch {
            // Never retain a new file whose protection/durability could not be
            // confirmed. Transaction callers still have an exact staged copy.
            if didWrite {
                try? fileManager.removeItem(at: url)
                try? synchronizeDirectory(url.deletingLastPathComponent())
            }
            throw error
        }
    }

    private func copyProtected(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.copyItem(at: source, to: destination)
            try applyCompleteProtection(to: destination)
            try synchronizeFile(at: destination)
            try synchronizeDirectory(destination.deletingLastPathComponent())
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    private func moveProtected(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            throw CatchRepositoryError.duplicateIdentifier
        }
        try fileManager.moveItem(at: source, to: destination)
        do {
            try applyCompleteProtection(to: destination)
            try synchronizeFile(at: destination)
            try synchronizeDirectory(source.deletingLastPathComponent())
            if source.deletingLastPathComponent() != destination.deletingLastPathComponent() {
                try synchronizeDirectory(destination.deletingLastPathComponent())
            }
        } catch {
            // Best effort puts the protected staged file back. If that move
            // also fails, the journal still identifies the destination exactly
            // and rollback removes it without scanning unrelated photos.
            try? fileManager.moveItem(at: destination, to: source)
            try? synchronizeDirectory(source.deletingLastPathComponent())
            try? synchronizeDirectory(destination.deletingLastPathComponent())
            throw error
        }
    }

    /// The journal's durable disappearance is the transaction commit point.
    private func removeJournalAtCommitPoint(_ transaction: CatchFileTransaction) throws {
        try fileManager.removeItem(at: paths.journalURL)
        do {
            try failureInjector(.syncJournalCommit)
            try synchronizeDirectory(paths.rootDirectory)
        } catch {
            // If a live directory sync reports failure, put the rollback marker
            // back before unwinding. The caller then restores the transaction;
            // if that restoration is interrupted, launch recovery still has a
            // durable journal rather than silently accepting a partial commit.
            try writeProtected(encoder.encode(transaction), to: paths.journalURL)
            throw error
        }
    }

    private func removeDurably(_ url: URL) throws {
        try fileManager.removeItem(at: url)
        try synchronizeDirectory(url.deletingLastPathComponent())
    }

    private func removeTransactionDirectoryBestEffort(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
            try synchronizeDirectory(paths.transactionsDirectory)
        } catch {
            // The journal is already absent (committed) or rollback restored
            // all user files. This directory contains only protected staging
            // copies and is retried by removeUnjournaledStaging on next load.
        }
    }

    private func synchronizeFile(at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    /// `Data.write(.atomic)` and FileManager rename/remove do not themselves
    /// make the parent directory entry durable. Synchronizing each ordering
    /// barrier prevents an acknowledged transaction from being reordered across
    /// a device reset.
    private func synchronizeDirectory(_ url: URL) throws {
        let descriptor = url.path.withCString { path in
            Darwin.open(path, O_RDONLY)
        }
        guard descriptor >= 0 else {
            throw posixError()
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw posixError()
        }
    }

    private func posixError() -> Error {
        if let code = POSIXErrorCode(rawValue: errno) {
            return POSIXError(code)
        }
        return CocoaError(.fileWriteUnknown)
    }

    private func validatedFilename(_ filename: String) throws -> String {
        guard !filename.isEmpty,
              filename == URL(fileURLWithPath: filename).lastPathComponent,
              filename != ".",
              filename != ".." else {
            throw CatchRepositoryError.invalidPhotoFilename
        }
        return filename
    }

    private func validatedPhotoURL(_ filename: String) throws -> URL {
        paths.photoURL(for: try validatedFilename(filename))
    }

    private func validatedThumbnailURL(_ filename: String) throws -> URL {
        paths.thumbnailURL(for: try validatedFilename(filename))
    }
}

/// Decodes one historical element at a time so a single malformed catch never
/// discards the rest of an otherwise recoverable log.
private struct FailableCatchEntry: Decodable {
    let value: CatchEntry?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(CatchEntry.self)
    }
}
