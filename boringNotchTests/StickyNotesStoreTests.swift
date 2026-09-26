//
//  StickyNotesStoreTests.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//
//  Saving and loading sticky notes in a throwaway directory: the round trip,
//  blank notes left out, a damaged file kept rather than overwritten, and
//  notes staying in backups.
//

import XCTest
@testable import boringNotch

final class StickyNotesStoreTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StickyNotesStoreTests-\(UUID().uuidString)", isDirectory: true)
    private var store: StickyNotesStore { StickyNotesStore(directory: directory) }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testLoadsNothingBeforeTheFirstSave() throws {
        XCTAssertEqual(try store.load(), StickyNotesDocument())
    }

    func testRoundTripsNotesColorsDatesAndTheNoteShowing() throws {
        let created = Date(timeIntervalSince1970: 1_790_000_000.123)
        let notes = [
            StickyNote(text: "Call the bank\nbefore 5", color: .blue, createdAt: created, modifiedAt: created.addingTimeInterval(90)),
            StickyNote(text: "Ideas", color: .charcoal, createdAt: created.addingTimeInterval(-600)),
            StickyNote(text: "ünïcödé ✓ 🗒️", color: .pink, createdAt: created.addingTimeInterval(-60))
        ]
        try store.save(StickyNotesDocument(notes: notes, currentNoteID: notes[2].id))

        let loaded = try store.load()
        let expected = StickyNotesDocument(notes: notes, currentNoteID: notes[2].id)
        XCTAssertEqual(loaded.notes.map(\.id), expected.notes.map(\.id))
        XCTAssertEqual(loaded.notes.map(\.text), expected.notes.map(\.text))
        XCTAssertEqual(loaded.notes.map(\.color), expected.notes.map(\.color))
        XCTAssertEqual(loaded.currentNoteID, notes[2].id)
        for (loadedNote, note) in zip(loaded.notes, expected.notes) {
            XCTAssertEqual(loadedNote.createdAt.timeIntervalSince1970, note.createdAt.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertEqual(loadedNote.modifiedAt.timeIntervalSince1970, note.modifiedAt.timeIntervalSince1970, accuracy: 0.001)
        }
    }

    func testLeavesBlankNotesOut() throws {
        var document = StickyNotesDocument(notes: [StickyNote(text: "kept")])
        document.createNote()
        try store.save(document)
        XCTAssertEqual(try store.load().notes.map(\.text), ["kept"])
    }

    func testKeepsADamagedFileInsteadOfOverwritingIt() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let damaged = Data("{\"notes\": [ {\"id\": ".utf8)
        try damaged.write(to: store.notesFile)

        var movedTo: URL?
        XCTAssertThrowsError(try store.load()) { error in
            guard case let StickyNotesStore.LoadError.unreadable(url, _) = error else {
                return XCTFail("Unexpected error \(error)")
            }
            movedTo = url
        }
        let aside = try XCTUnwrap(movedTo)
        XCTAssertEqual(try Data(contentsOf: aside), damaged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.notesFile.path))

        try store.save(StickyNotesDocument(notes: [StickyNote(text: "new")]))
        XCTAssertEqual(try Data(contentsOf: aside), damaged)
        XCTAssertEqual(try store.load().notes.map(\.text), ["new"])
    }

    func testKeepsNotesInBackups() throws {
        try store.save(StickyNotesDocument(notes: [StickyNote(text: "backed up")]))
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertNotEqual(values.isExcludedFromBackup, true)
    }

    func testWritesAReadableFile() throws {
        try store.save(StickyNotesDocument(notes: [StickyNote(text: "readable", createdAt: Date(timeIntervalSince1970: 0))]))
        let json = try String(contentsOf: store.notesFile, encoding: .utf8)
        XCTAssertTrue(json.contains("\"version\" : 1"), json)
        XCTAssertTrue(json.contains("\"text\" : \"readable\""), json)
        XCTAssertTrue(json.contains("\"createdAt\" : \"1970-01-01T00:00:00.000Z\""), json)
    }
}
