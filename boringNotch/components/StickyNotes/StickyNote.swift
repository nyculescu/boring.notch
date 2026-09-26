//
//  StickyNote.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import Foundation

/// One sticky note, as kept in memory and saved to disk.
struct StickyNote: Identifiable, Equatable, Codable {
    let id: UUID
    var text: String
    var color: StickyNoteColor
    let createdAt: Date
    /// When the text or color last changed. Notes are listed, and swiped
    /// through, newest first by this.
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        text: String = "",
        color: StickyNoteColor = .yellow,
        createdAt: Date = Date(),
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.color = color
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
    }

    /// Nothing written yet. A blank note isn't saved, and goes away when you
    /// move to another note, like an empty note closed in Windows.
    var isBlank: Bool {
        text.allSatisfy(\.isWhitespace)
    }

    /// The first lines, for the notes list: leading blank lines dropped and
    /// capped, so a long note stays cheap to render.
    var previewText: String {
        let lines = text.prefix(600)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.prefix(4).joined(separator: "\n")
    }
}

/// The colors of Windows Sticky Notes, in the order its menu shows them.
enum StickyNoteColor: String, Codable, CaseIterable {
    case yellow, green, pink, purple, blue, gray, charcoal

    /// The note itself, as 0xRRGGBB.
    var paper: UInt32 {
        switch self {
        case .yellow: 0xFFF7D1
        case .green: 0xE4F9E0
        case .pink: 0xFFE4F1
        case .purple: 0xF2E6FF
        case .blue: 0xE2F1FF
        case .gray: 0xF3F2F1
        case .charcoal: 0x696969
        }
    }

    /// The stronger band along the note's top edge, as 0xRRGGBB.
    var band: UInt32 {
        switch self {
        case .yellow: 0xFFF2AB
        case .green: 0xCBF1C4
        case .pink: 0xFFCCE5
        case .purple: 0xE7CFFF
        case .blue: 0xCDE9FF
        case .gray: 0xE1DFDD
        case .charcoal: 0x494745
        }
    }

    /// Charcoal takes light text; the rest take dark text.
    var isDark: Bool {
        self == .charcoal
    }

    /// A color this version doesn't know (saved by a newer one) reads as
    /// yellow instead of making the whole file unreadable.
    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = StickyNoteColor(rawValue: rawValue) ?? .yellow
    }
}

/// All the notes, newest first, and the one the notch shows. Every change
/// keeps that order, so the notes list and swiping always agree.
struct StickyNotesDocument: Equatable, Codable {
    private(set) var notes: [StickyNote]
    /// The note you last looked at or wrote in. It can point at a note that
    /// wasn't saved (a blank one), in which case the newest note shows.
    private(set) var currentNoteID: UUID?

    init(notes: [StickyNote] = [], currentNoteID: UUID? = nil) {
        self.notes = notes.sorted(by: Self.newestFirst)
        self.currentNoteID = currentNoteID
    }

    // MARK: Codable

    /// Written with the notes, for whatever a later format needs to migrate.
    static let formatVersion = 1

    private enum CodingKeys: String, CodingKey {
        case version, notes, currentNoteID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            notes: try container.decode([StickyNote].self, forKey: .notes),
            currentNoteID: try container.decodeIfPresent(UUID.self, forKey: .currentNoteID)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .version)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(currentNoteID, forKey: .currentNoteID)
    }

    // MARK: Notes

    var currentNote: StickyNote? {
        notes.first { $0.id == currentNoteID } ?? notes.first
    }

    var currentIndex: Int? {
        guard let id = currentNote?.id else { return nil }
        return notes.firstIndex { $0.id == id }
    }

    /// What gets written to disk: blank notes are left out.
    var saved: StickyNotesDocument {
        StickyNotesDocument(notes: notes.filter { !$0.isBlank }, currentNoteID: currentNoteID)
    }

    /// Gives the notch a note to write in when there are none.
    mutating func ensureNote(now: Date = Date()) {
        guard notes.isEmpty else { return }
        let note = StickyNote(createdAt: now)
        notes = [note]
        currentNoteID = note.id
    }

    /// Starts a note in the color of the one showing, as the first note is
    /// yellow. While the note showing is still blank, that one is reused.
    @discardableResult
    mutating func createNote(now: Date = Date()) -> StickyNote {
        if let current = currentNote, current.isBlank {
            return current
        }
        let note = StickyNote(color: currentNote?.color ?? .yellow, createdAt: now)
        notes.insert(note, at: 0)
        notes.sort(by: Self.newestFirst)
        currentNoteID = note.id
        return note
    }

    /// Shows another note, dropping the one you leave if it's blank.
    mutating func select(_ id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        if let leaving = currentNote, leaving.id != id, leaving.isBlank {
            notes.removeAll { $0.id == leaving.id }
        }
        currentNoteID = id
    }

    /// Moves `offset` notes along: +1 to the next older note, -1 to the next
    /// newer one. Returns false at either end.
    @discardableResult
    mutating func selectNeighbor(_ offset: Int) -> Bool {
        guard let index = currentIndex, notes.indices.contains(index + offset) else { return false }
        select(notes[index + offset].id)
        return true
    }

    // MARK: Two notes side by side

    /// The two notes the full-size notch shows: the note showing and the
    /// next older one, or the two oldest when it's the oldest. Usually
    /// that's the two notes written in last.
    var currentPair: [StickyNote] {
        pair(startingAt: currentIndex ?? 0)
    }

    /// Two neighboring notes from `index`, moved back when `index` is the
    /// oldest so there are still two; fewer only when there aren't two notes.
    func pair(startingAt index: Int) -> [StickyNote] {
        guard !notes.isEmpty else { return [] }
        let start = min(max(index, 0), max(notes.count - 2, 0))
        return Array(notes[start..<min(start + 2, notes.count)])
    }

    /// The pair one note along from the one on screen: +1 toward older
    /// notes, -1 toward newer ones, nil at either end. Writing in a note
    /// moves it first in the order, so the pair on screen may be out of
    /// order; the step is taken from its older or newer note.
    func neighborPair(of shown: [UUID], offset: Int) -> [StickyNote]? {
        let indices = shown.compactMap { id in notes.firstIndex { $0.id == id } }
        guard offset != 0, let newest = indices.min(), let oldest = indices.max() else { return nil }
        let start = offset > 0 ? oldest + offset - 1 : newest + offset
        guard start >= 0, start + 1 < notes.count else { return nil }
        return [notes[start], notes[start + 1]]
    }

    /// Whether the pair on screen should give way to `currentPair`: one of
    /// its notes is gone, the note showing isn't in it (a new note, one
    /// opened from the notes list), or it has room for another note.
    /// Writing in a note never counts, so the notes don't swap places
    /// under the caret.
    func pairNeedsRefresh(_ shown: [UUID]) -> Bool {
        if shown.contains(where: { id in !notes.contains { $0.id == id } }) { return true }
        if let current = currentNote?.id, !shown.contains(current) { return true }
        return shown.count < min(2, notes.count)
    }

    /// Writing in a note makes it the newest, and the one showing.
    mutating func updateText(_ text: String, of id: UUID, now: Date = Date()) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        notes[index].text = text
        notes[index].modifiedAt = now
        notes.sort(by: Self.newestFirst)
        currentNoteID = id
    }

    mutating func setColor(_ color: StickyNoteColor, of id: UUID, now: Date = Date()) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].color != color else { return }
        notes[index].color = color
        notes[index].modifiedAt = now
        notes.sort(by: Self.newestFirst)
    }

    /// Removes a note. If it was showing, the next older note shows instead,
    /// or the next newer one when it was the oldest.
    @discardableResult
    mutating func delete(_ id: UUID) -> StickyNote? {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return nil }
        let wasCurrent = currentNote?.id == id
        let note = notes.remove(at: index)
        if wasCurrent {
            currentNoteID = notes.isEmpty ? nil : notes[min(index, notes.count - 1)].id
        }
        return note
    }

    @discardableResult
    mutating func deleteAll() -> [StickyNote] {
        let removed = notes
        notes = []
        currentNoteID = nil
        return removed
    }

    /// Puts deleted notes back where their dates place them. A blank note
    /// showing in the meantime gives way to the newest one restored.
    mutating func restore(_ restored: [StickyNote]) {
        let missing = restored.filter { note in !notes.contains { $0.id == note.id } }
        guard !missing.isEmpty else { return }
        notes.append(contentsOf: missing)
        notes.sort(by: Self.newestFirst)
        if currentNote?.isBlank ?? true, let newest = missing.sorted(by: Self.newestFirst).first {
            select(newest.id)
        }
    }

    private static func newestFirst(_ lhs: StickyNote, _ rhs: StickyNote) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt {
            return lhs.modifiedAt > rhs.modifiedAt
        }
        return lhs.createdAt > rhs.createdAt
    }
}
