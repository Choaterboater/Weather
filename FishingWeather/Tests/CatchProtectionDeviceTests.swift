#if os(iOS) && !targetEnvironment(simulator)
import Foundation
import Testing
import UIKit
@testable import BiteCast

/// Hardware-backed evidence for the effective protection class. Simulator
/// tests verify every production request; this test reads what iOS actually
/// applied at the synchronous recorder boundary after each setAttributes call.
@MainActor
@Suite("Catch file protection (physical device)")
struct CatchProtectionDeviceTests {
    private final class ActualProtectionRecorder {
        struct Observation {
            let url: URL
            let protection: FileProtectionType?
            let rawProtection: String
            let readError: String?
        }

        private(set) var observations: [Observation] = []

        func record(url: URL, requestedProtection: FileProtectionType) {
            let standardizedURL = url.standardizedFileURL
            do {
                let attributes = try FileManager.default.attributesOfItem(
                    atPath: standardizedURL.path
                )
                let rawValue = attributes[.protectionKey]
                let actualProtection: FileProtectionType?
                if let typedValue = rawValue as? FileProtectionType {
                    actualProtection = typedValue
                } else if let stringValue = rawValue as? String {
                    actualProtection = FileProtectionType(rawValue: stringValue)
                } else {
                    actualProtection = nil
                }
                observations.append(Observation(
                    url: standardizedURL,
                    protection: actualProtection,
                    rawProtection: rawValue.map { String(describing: $0) } ?? "nil",
                    readError: nil
                ))
            } catch {
                observations.append(Observation(
                    url: standardizedURL,
                    protection: nil,
                    rawProtection: "unreadable",
                    readError: error.localizedDescription
                ))
            }

            #expect(
                requestedProtection == .complete,
                "Production requested a protection class other than complete for \(standardizedURL.path)"
            )
        }

        func directChildren(of directory: URL) -> [URL] {
            let parentPath = directory.standardizedFileURL.path
            return Array(Set(observations.lazy.map(\.url).filter {
                $0.deletingLastPathComponent().standardizedFileURL.path == parentPath
            })).sorted { $0.path < $1.path }
        }

        func expectComplete(at url: URL, role: String) {
            let path = url.standardizedFileURL.path
            let matching = observations.filter { $0.url.path == path }
            #expect(
                !matching.isEmpty,
                "No synchronous protection observation was recorded for \(role): \(path)"
            )
            #expect(
                matching.allSatisfy {
                    $0.readError == nil && $0.protection == .complete
                },
                "\(role) did not report complete protection: \(matching.map { $0.readError ?? $0.rawProtection })"
            )
        }
    }

    @Test("A complete catch transaction has complete hardware file protection")
    func physicalCatchTransactionUsesCompleteFileProtection() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(
            "CatchProtectionDeviceTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            do {
                if fileManager.fileExists(atPath: directory.path) {
                    try fileManager.removeItem(at: directory)
                }
                #expect(!fileManager.fileExists(atPath: directory.path))
            } catch {
                Issue.record("Could not remove physical protection test data: \(error)")
            }
        }

        let recorder = ActualProtectionRecorder()
        let log = CatchLog(
            directory: directory,
            protectionRecorder: recorder.record
        )
        let requestedEntry = CatchEntry(species: .bass, bait: "device evidence")
        try log.add(requestedEntry, photo: makeTinyPhoto())

        let savedEntry = try #require(log.entries.first {
            $0.id == requestedEntry.id
        })
        let filename = try #require(savedEntry.photoFilename)
        let paths = log.storagePaths
        let transactionDirectories = recorder.directChildren(
            of: paths.transactionsDirectory
        )
        #expect(transactionDirectories.count == 1)
        let transactionDirectory = try #require(transactionDirectories.first)

        let stagedPhotoURL = transactionDirectory.appendingPathComponent("photo.jpg")
        let stagedThumbnailURL = transactionDirectory.appendingPathComponent("thumbnail.jpg")
        let finalPhotoURL = paths.photoURL(for: filename)
        let finalThumbnailURL = paths.thumbnailURL(for: filename)

        let requiredProtection: [(URL, String)] = [
            (paths.rootDirectory, "catch root directory"),
            (paths.photosDirectory, "photos directory"),
            (paths.transactionsDirectory, "transactions directory"),
            (transactionDirectory, "transaction staging directory"),
            (stagedPhotoURL, "staged photo"),
            (stagedThumbnailURL, "staged thumbnail"),
            (paths.journalURL, "rollback journal"),
            (finalPhotoURL, "final photo"),
            (finalThumbnailURL, "final thumbnail"),
            (paths.metadataURL, "catch metadata"),
        ]
        for (url, role) in requiredProtection {
            recorder.expectComplete(at: url, role: role)
        }

        #expect(recorder.observations.allSatisfy { $0.readError == nil })
        #expect(recorder.observations.allSatisfy { $0.protection == .complete })
        #expect(fileManager.fileExists(atPath: finalPhotoURL.path))
        #expect(fileManager.fileExists(atPath: finalThumbnailURL.path))
        #expect(fileManager.fileExists(atPath: paths.metadataURL.path))
        #expect(!fileManager.fileExists(atPath: paths.journalURL.path))
        #expect(!fileManager.fileExists(atPath: transactionDirectory.path))
    }

    private func makeTinyPhoto() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
#endif
