//
//  StickyNotesStore.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import Foundation

/// Saves sticky notes inside Boring Notch's container, so they survive
/// quitting, restarting the Mac and turning the feature off. Unlike clipboard
/// history, notes are your own writing, so they stay in backups. Not
/// thread-safe: use it from one queue.
struct StickyNotesStore {
    let directory: URL

    enum LoadError: Error {
        /// The file couldn't be read or decoded. It was moved to `movedTo`
        /// (nil if even that failed), so that no later save overwrites it.
        case unreadable(movedTo: URL?, underlying: Error)
    }

    static var standard: StickyNotesStore {
        let fileManager = FileManager.default
        let support = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        return StickyNotesStore(
            directory: support
                .appendingPathComponent("boringNotch", isDirectory: true)
                .appendingPathComponent("StickyNotes", isDirectory: true)
        )
    }

    var notesFile: URL { directory.appendingPathComponent("notes.json") }

    /// The saved notes, or none before the first save.
    func load() throws -> StickyNotesDocument {
        guard FileManager.default.fileExists(atPath: notesFile.path) else {
            return StickyNotesDocument()
        }
        do {
            let data = try Data(contentsOf: notesFile)
            return try Self.decoder().decode(StickyNotesDocument.self, from: data)
        } catch {
            throw LoadError.unreadable(movedTo: moveAside(), underlying: error)
        }
    }

    /// Writes the notes worth keeping: blank ones are left out.
    func save(_ document: StickyNotesDocument) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder().encode(document.saved).write(to: notesFile, options: .atomic)
    }

    private func moveAside() -> URL? {
        let destination = directory.appendingPathComponent("notes-unreadable-\(Int(Date().timeIntervalSince1970)).json")
        do {
            try FileManager.default.moveItem(at: notesFile, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private static let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Readable, so notes could be recovered by hand if it ever came to that.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateFormat))
        }
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = try? dateFormat.parse(string) {
                return date
            }
            return try Date.ISO8601FormatStyle().parse(string)
        }
        return decoder
    }
}
