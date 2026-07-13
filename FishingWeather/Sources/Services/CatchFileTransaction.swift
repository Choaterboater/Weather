import Foundation

/// Testable checkpoints around the private catch-history filesystem.
///
/// Production never injects failures. Focused tests use these points to prove
/// that each boundary either commits completely or restores the prior log.
enum CatchFileFailurePoint: String, Hashable, Sendable {
    case prepareDirectories
    case migrateProtection
    case stageMetadata
    case stagePhoto
    case stageThumbnail
    case writeJournal
    case installPhoto
    case installThumbnail
    case replaceMetadata
    case removePhoto
    case removeThumbnail
    case removeJournal
    case recoveryMetadata
    case recoveryPhoto
    case writeThumbnail
    case syncJournalCommit
}

/// A protected, durable marker for a catch-history mutation.
///
/// Journal presence means the transaction is not committed. Recovery always
/// restores `originalEntries` and the pre-transaction files. Removing the
/// journal is the single commit point, which keeps recovery deterministic even
/// if the process is killed between any two filesystem calls.
struct CatchFileTransaction: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case add
        case remove
    }

    static let currentVersion = 1

    let version: Int
    let id: UUID
    let kind: Kind
    let originalEntries: [CatchEntry]
    let metadataExisted: Bool
    let photoFilename: String?
    let includesPhotoMutation: Bool
    let includesThumbnailMutation: Bool
    let photoExisted: Bool
    let thumbnailExisted: Bool

    init(
        id: UUID = UUID(),
        kind: Kind,
        originalEntries: [CatchEntry],
        metadataExisted: Bool,
        photoFilename: String?,
        includesPhotoMutation: Bool,
        includesThumbnailMutation: Bool,
        photoExisted: Bool,
        thumbnailExisted: Bool
    ) {
        version = Self.currentVersion
        self.id = id
        self.kind = kind
        self.originalEntries = originalEntries
        self.metadataExisted = metadataExisted
        self.photoFilename = photoFilename
        self.includesPhotoMutation = includesPhotoMutation
        self.includesThumbnailMutation = includesThumbnailMutation
        self.photoExisted = photoExisted
        self.thumbnailExisted = thumbnailExisted
    }

    var directoryName: String { id.uuidString.lowercased() }
}

enum CatchRepositoryError: LocalizedError {
    case duplicateIdentifier
    case photoCollision
    case invalidPhotoFilename
    case malformedJournal
    case missingRecoveryFile(String)
    case operationFailed(action: String, reason: String)
    case recoveryRequired(action: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .duplicateIdentifier:
            "That catch already exists. Nothing was changed."
        case .photoCollision:
            "A private photo already uses this catch identifier. Nothing was changed or removed."
        case .invalidPhotoFilename:
            "The saved photo name is invalid. Nothing was changed."
        case .malformedJournal:
            "Catch history needs recovery, but its recovery journal is unreadable. Your files were left untouched."
        case .missingRecoveryFile(let name):
            "Catch history needs recovery, but \(name) is missing. Your remaining files were left untouched."
        case .operationFailed(let action, let reason):
            "Couldn't \(action) the catch. Nothing was changed. \(reason)"
        case .recoveryRequired(let action, let reason):
            "Couldn't \(action) the catch. The previous log is still shown and recovery will retry next launch. \(reason)"
        }
    }
}
