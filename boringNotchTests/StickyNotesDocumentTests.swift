//
//  StickyNotesDocumentTests.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//
//  The rules the Sticky Notes tab and the notes list share: newest first,
//  which note shows, new notes and their colors, blank notes going away,
//  moving between notes, deleting and bringing notes back.
//

import XCTest
@testable import boringNotch

final class StickyNotesDocumentTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func note(_ text: String, color: StickyNoteColor = .yellow, minutesAgo: Double) -> StickyNote {
        let date = start.addingTimeInterval(-minutesAgo * 60)
        return StickyNote(text: text, color: color, createdAt: date, modifiedAt: date)
    }

    /// Three notes, newest first: "new", "mid", "old".
    private func threeNotes() -> StickyNotesDocument {
        StickyNotesDocument(notes: [
            note("old", minutesAgo: 30),
            note("new", minutesAgo: 10),
            note("mid", minutesAgo: 20)
        ])
    }

    private func texts(_ document: StickyNotesDocument) -> [String] {
        document.notes.map(\.text)
    }

    // MARK: - Order and the note showing

    func testKeepsNotesNewestFirst() {
        XCTAssertEqual(texts(threeNotes()), ["new", "mid", "old"])
    }

    func testShowsTheNewestNoteWhenTheOneLastShownIsGone() {
        let document = StickyNotesDocument(notes: threeNotes().notes, currentNoteID: UUID())
        XCTAssertEqual(document.currentNote?.text, "new")
        XCTAssertEqual(document.currentIndex, 0)
    }

    func testShowsTheNoteLastShown() {
        let notes = threeNotes().notes
        let document = StickyNotesDocument(notes: notes, currentNoteID: notes[2].id)
        XCTAssertEqual(document.currentNote?.text, "old")
        XCTAssertEqual(document.currentIndex, 2)
    }

    func testGivesAnEmptyDocumentABlankYellowNoteToWriteIn() {
        var document = StickyNotesDocument()
        document.ensureNote(now: start)
        XCTAssertEqual(document.notes.count, 1)
        XCTAssertEqual(document.currentNote?.color, .yellow)
        XCTAssertEqual(document.currentNote?.isBlank, true)

        var written = threeNotes()
        written.ensureNote(now: start)
        XCTAssertEqual(texts(written), ["new", "mid", "old"])
    }

    // MARK: - New notes

    func testNewNoteTakesTheColorOfTheNoteShowingAndComesFirst() {
        var document = StickyNotesDocument(notes: [note("blue", color: .blue, minutesAgo: 5)])
        let created = document.createNote(now: start)
        XCTAssertEqual(created.color, .blue)
        XCTAssertEqual(document.notes.first?.id, created.id)
        XCTAssertEqual(document.currentNote?.id, created.id)
    }

    func testFirstNoteIsYellow() {
        var document = StickyNotesDocument()
        XCTAssertEqual(document.createNote(now: start).color, .yellow)
    }

    func testNewNoteReusesABlankNoteThatIsShowing() {
        var document = threeNotes()
        let blank = document.createNote(now: start)
        let again = document.createNote(now: start.addingTimeInterval(1))
        XCTAssertEqual(again.id, blank.id)
        XCTAssertEqual(document.notes.count, 4)
    }

    // MARK: - Writing and colors

    func testWritingInANoteMakesItTheNewestAndTheOneShowing() {
        var document = threeNotes()
        let old = document.notes[2]
        let now = start.addingTimeInterval(60)
        document.updateText("old, edited", of: old.id, now: now)
        XCTAssertEqual(texts(document), ["old, edited", "new", "mid"])
        XCTAssertEqual(document.notes[0].modifiedAt, now)
        XCTAssertEqual(document.notes[0].createdAt, old.createdAt)
        XCTAssertEqual(document.currentNote?.id, old.id)
    }

    func testWritingTheSameTextChangesNothing() {
        var document = threeNotes()
        let before = document
        document.updateText("mid", of: document.notes[1].id, now: start.addingTimeInterval(60))
        XCTAssertEqual(document, before)
    }

    func testChangingColorKeepsTheTextAndCountsAsAChange() {
        var document = threeNotes()
        let mid = document.notes[1]
        document.setColor(.charcoal, of: mid.id, now: start.addingTimeInterval(60))
        XCTAssertEqual(document.notes[0].id, mid.id)
        XCTAssertEqual(document.notes[0].color, .charcoal)
        XCTAssertEqual(document.notes[0].text, "mid")
    }

    // MARK: - Moving between notes

    func testStepsThroughNotesAndStopsAtEitherEnd() {
        var document = threeNotes()
        XCTAssertFalse(document.selectNeighbor(-1))
        XCTAssertTrue(document.selectNeighbor(1))
        XCTAssertEqual(document.currentNote?.text, "mid")
        XCTAssertTrue(document.selectNeighbor(1))
        XCTAssertEqual(document.currentNote?.text, "old")
        XCTAssertFalse(document.selectNeighbor(1))
        XCTAssertEqual(document.currentNote?.text, "old")
        XCTAssertTrue(document.selectNeighbor(-2))
        XCTAssertEqual(document.currentNote?.text, "new")
    }

    // MARK: - Two notes side by side

    private func texts(_ notes: [StickyNote]) -> [String] {
        notes.map(\.text)
    }

    private func ids(_ document: StickyNotesDocument, _ texts: String...) -> [UUID] {
        texts.compactMap { text in document.notes.first { $0.text == text }?.id }
    }

    func testThePairIsTheTwoNotesWrittenInLast() {
        XCTAssertEqual(texts(threeNotes().currentPair), ["new", "mid"])
    }

    func testThePairKeepsTwoNotesWhenTheOldestShows() {
        var document = threeNotes()
        document.selectNeighbor(2)
        XCTAssertEqual(texts(document.currentPair), ["mid", "old"])
        XCTAssertEqual(texts(document.pair(startingAt: 99)), ["mid", "old"])
        XCTAssertEqual(texts(document.pair(startingAt: -1)), ["new", "mid"])
    }

    func testASingleNoteMakesAPairOfOne() {
        let document = StickyNotesDocument(notes: [note("only", minutesAgo: 1)])
        XCTAssertEqual(texts(document.currentPair), ["only"])
        XCTAssertEqual(StickyNotesDocument().currentPair, [])
    }

    func testSwipingMovesThePairOneNoteAlongAndStopsAtEitherEnd() {
        let document = threeNotes()
        let first = ids(document, "new", "mid")
        XCTAssertNil(document.neighborPair(of: first, offset: -1))
        let older = document.neighborPair(of: first, offset: 1)
        XCTAssertEqual(older.map(texts), ["mid", "old"])
        XCTAssertNil(document.neighborPair(of: ids(document, "mid", "old"), offset: 1))
        XCTAssertEqual(document.neighborPair(of: ids(document, "mid", "old"), offset: -1).map(texts), ["new", "mid"])
    }

    func testSwipingAfterWritingInTheRightNoteGoesByItsOlderNote() {
        var document = threeNotes()
        let shown = ids(document, "new", "mid")
        // Writing in "mid" makes it the newest: the order is now mid, new, old.
        document.updateText("mid!", of: shown[1], now: start)
        XCTAssertEqual(document.neighborPair(of: shown, offset: 1).map(texts), ["new", "old"])
        XCTAssertNil(document.neighborPair(of: shown, offset: -1))
    }

    func testWritingInEitherNoteKeepsThePairOnScreen() {
        var document = threeNotes()
        let shown = ids(document, "new", "mid")
        document.updateText("mid!", of: shown[1], now: start)
        XCTAssertFalse(document.pairNeedsRefresh(shown))
        document.updateText("new!", of: shown[0], now: start.addingTimeInterval(1))
        XCTAssertFalse(document.pairNeedsRefresh(shown))
    }

    func testANewNoteJoinsThePairOnTheLeft() {
        var document = threeNotes()
        let shown = ids(document, "new", "mid")
        document.createNote(now: start.addingTimeInterval(60))
        XCTAssertTrue(document.pairNeedsRefresh(shown))
        XCTAssertEqual(texts(document.currentPair), ["", "new"])
    }

    func testOpeningAnotherNoteFromTheListShowsIt() {
        var document = threeNotes()
        let shown = ids(document, "new", "mid")
        document.select(ids(document, "mid")[0])
        XCTAssertFalse(document.pairNeedsRefresh(shown), "Already on screen")
        document.select(ids(document, "old")[0])
        XCTAssertTrue(document.pairNeedsRefresh(shown))
        XCTAssertEqual(texts(document.currentPair), ["mid", "old"])
    }

    func testDeletingANoteOnScreenRefillsThePair() {
        var document = threeNotes()
        let shown = ids(document, "new", "mid")
        document.delete(shown[1])
        XCTAssertTrue(document.pairNeedsRefresh(shown))
        XCTAssertEqual(texts(document.currentPair), ["new", "old"])
    }

    func testAPairOfOneGrowsWhenASecondNoteArrives() {
        var document = StickyNotesDocument(notes: [note("only", minutesAgo: 1)])
        let shown = document.currentPair.map(\.id)
        XCTAssertFalse(document.pairNeedsRefresh(shown))
        document.restore([note("back", minutesAgo: 5)])
        XCTAssertTrue(document.pairNeedsRefresh(shown))
        XCTAssertEqual(texts(document.currentPair), ["only", "back"])
    }

    func testLeavingABlankNoteDropsIt() {
        var document = threeNotes()
        document.createNote(now: start)
        XCTAssertEqual(document.notes.count, 4)
        XCTAssertTrue(document.selectNeighbor(1))
        XCTAssertEqual(texts(document), ["new", "mid", "old"])
        XCTAssertEqual(document.currentNote?.text, "new")
    }

    func testLeavingANoteWithOnlySpacesDropsItToo() {
        var document = threeNotes()
        let created = document.createNote(now: start)
        document.updateText("  \n\t", of: created.id, now: start.addingTimeInterval(1))
        document.select(document.notes[2].id)
        XCTAssertEqual(texts(document), ["new", "mid", "old"])
    }

    func testLeavingAWrittenNoteKeepsIt() {
        var document = threeNotes()
        let created = document.createNote(now: start)
        document.updateText("keep me", of: created.id, now: start.addingTimeInterval(1))
        document.selectNeighbor(1)
        XCTAssertEqual(texts(document), ["keep me", "new", "mid", "old"])
    }

    // MARK: - Deleting

    func testDeletingTheNoteShowingShowsTheNextOlderOne() {
        var document = threeNotes()
        document.select(document.notes[1].id)
        let deleted = document.delete(document.notes[1].id)
        XCTAssertEqual(deleted?.text, "mid")
        XCTAssertEqual(document.currentNote?.text, "old")
    }

    func testDeletingTheOldestNoteWhileItShowsShowsTheNextNewerOne() {
        var document = threeNotes()
        document.select(document.notes[2].id)
        document.delete(document.notes[2].id)
        XCTAssertEqual(document.currentNote?.text, "mid")
    }

    func testDeletingAnotherNoteLeavesTheOneShowing() {
        var document = threeNotes()
        document.select(document.notes[1].id)
        document.delete(document.notes[2].id)
        XCTAssertEqual(document.currentNote?.text, "mid")
    }

    func testDeletingTheLastNoteLeavesNothingShowing() {
        var document = StickyNotesDocument(notes: [note("only", minutesAgo: 1)])
        document.delete(document.notes[0].id)
        XCTAssertNil(document.currentNote)
        XCTAssertNil(document.currentNoteID)
    }

    func testRestoringPutsNotesBackInOrderAndReplacesABlankNote() {
        var document = threeNotes()
        let removed = document.deleteAll()
        XCTAssertTrue(document.notes.isEmpty)
        document.ensureNote(now: start)

        document.restore(removed)
        XCTAssertEqual(texts(document), ["new", "mid", "old"])
        XCTAssertEqual(document.currentNote?.text, "new")
    }

    func testRestoringOneNoteKeepsTheNoteShowing() {
        var document = threeNotes()
        let mid = document.delete(document.notes[1].id)!
        document.select(document.notes[1].id)
        document.restore([mid])
        XCTAssertEqual(texts(document), ["new", "mid", "old"])
        XCTAssertEqual(document.currentNote?.text, "old")
    }

    // MARK: - Saving

    func testSavedFormLeavesOutBlankNotes() {
        var document = threeNotes()
        let created = document.createNote(now: start)
        let saved = document.saved
        XCTAssertEqual(texts(saved), ["new", "mid", "old"])
        XCTAssertEqual(saved.currentNoteID, created.id)
    }

    func testReadsAColorItDoesNotKnowAsYellow() throws {
        let json = """
        {"id":"\(UUID().uuidString)","text":"hi","color":"teal","createdAt":0,"modifiedAt":0}
        """
        let decoded = try JSONDecoder().decode(StickyNote.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.color, .yellow)
        XCTAssertEqual(decoded.text, "hi")
    }

    func testPreviewSkipsBlankLinesAndKeepsTheFirstFour() {
        let note = StickyNote(text: "\n\n  Groceries \n\nmilk\neggs\nbread\ncoffee")
        XCTAssertEqual(note.previewText, "Groceries\nmilk\neggs\nbread")
    }
}
