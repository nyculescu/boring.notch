//
//  StickyNotesManager.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import Combine
import Foundation

extension Notification.Name {
    /// Asks for the notch to open on the Sticky Notes tab (see AppDelegate).
    static let showStickyNotesInNotch = Notification.Name("theboringteam.boringnotch.showStickyNotesInNotch")
}

/// Keeps the sticky notes, and saves them as you type, so they're back after
/// quitting, restarting the Mac or turning the feature off.
@MainActor
final class StickyNotesManager: ObservableObject {
    static let shared = StickyNotesManager()

    /// Asks the note showing in the notch to take the keyboard, after + or
    /// when a note is opened from the notes list.
    struct FocusRequest: Equatable {
        let id = UUID()
        let date = Date()
        /// False when the request comes from outside the notch.
        let pointerIsOnNotch: Bool
    }

    @Published private(set) var document = StickyNotesDocument()
    /// The notes deleted last, which the notes list offers to bring back for a while.
    @Published private(set) var recentlyDeleted: [StickyNote] = []
    @Published private(set) var focusRequest: FocusRequest?

    /// Changes are written this soon after the first one, so continuous
    /// typing saves twice a second and nothing waits for a pause.
    private static let saveDelay: Duration = .milliseconds(500)
    private static let undoDeleteDuration: Duration = .seconds(10)
    private static let focusRequestLifetime: TimeInterval = 2

    private let store: StickyNotesStore
    /// Serializes all disk work, so saves land in order.
    private let storageQueue = DispatchQueue(label: "theboringteam.boringnotch.stickynotes.storage", qos: .utility)
    private var saveTask: Task<Void, Never>?
    private var forgetDeletedTask: Task<Void, Never>?
    private var hasUnsavedChanges = false
    private var didLoad = false
    /// Off when a file that couldn't be read couldn't be moved aside either:
    /// saving would overwrite whatever is left of the notes.
    private var canSave = true

    private init(store: StickyNotesStore = .standard) {
        self.store = store
    }

    var currentNote: StickyNote? { document.currentNote }

    /// Notes with something written in them: what the notes list shows.
    var writtenNotes: [StickyNote] {
        document.notes.filter { !$0.isBlank }
    }

    /// Loads the saved notes. Call once at launch, before anything shows them.
    func load() {
        guard !didLoad else { return }
        do {
            document = try store.load()
            Log.stickyNotes.debug("Loaded \(self.document.notes.count) sticky notes")
        } catch let StickyNotesStore.LoadError.unreadable(movedTo, underlying) {
            if let movedTo {
                Log.stickyNotes.error("Couldn't read the saved notes (\(underlying.localizedDescription, privacy: .public)), moved them to \(movedTo.path, privacy: .public)")
            } else {
                canSave = false
                Log.stickyNotes.fault("Couldn't read the saved notes or move them aside (\(underlying.localizedDescription, privacy: .public)), so they won't be saved over")
            }
        } catch {
            Log.stickyNotes.error("Couldn't load sticky notes: \(error.localizedDescription, privacy: .public)")
        }
        didLoad = true
    }

    // MARK: - Notes

    func ensureNote() {
        update { $0.ensureNote() }
    }

    func createNote() {
        update { $0.createNote() }
    }

    func select(_ id: UUID) {
        update { $0.select(id) }
    }

    /// +1 moves to the next older note, -1 to the next newer one. False at either end.
    @discardableResult
    func selectNeighbor(_ offset: Int) -> Bool {
        var moved = false
        update { moved = $0.selectNeighbor(offset) }
        return moved
    }

    func updateText(_ text: String, of id: UUID) {
        update { $0.updateText(text, of: id) }
    }

    func setColor(_ color: StickyNoteColor, of id: UUID) {
        update { $0.setColor(color, of: id) }
    }

    func delete(_ id: UUID) {
        var removed: StickyNote?
        update { removed = $0.delete(id) }
        if let removed, !removed.isBlank {
            rememberDeleted([removed])
        }
    }

    func deleteAll() {
        var removed: [StickyNote] = []
        update { removed = $0.deleteAll() }
        rememberDeleted(removed.filter { !$0.isBlank })
    }

    /// Brings back what was deleted last.
    func undoDelete() {
        let restored = recentlyDeleted
        forgetDeletedTask?.cancel()
        recentlyDeleted = []
        update { $0.restore(restored) }
    }

    private func update(_ change: (inout StickyNotesDocument) -> Void) {
        var changed = document
        change(&changed)
        guard changed != document else { return }
        document = changed
        scheduleSave()
    }

    private func rememberDeleted(_ notes: [StickyNote]) {
        guard !notes.isEmpty else { return }
        recentlyDeleted = notes
        forgetDeletedTask?.cancel()
        forgetDeletedTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.undoDeleteDuration)
            guard !Task.isCancelled else { return }
            self?.recentlyDeleted = []
        }
    }

    // MARK: - Keyboard

    func requestFocus(pointerIsOnNotch: Bool) {
        focusRequest = FocusRequest(pointerIsOnNotch: pointerIsOnNotch)
    }

    /// The pending request, handed out once. One nothing picked up within a
    /// couple of seconds (the notch didn't open) is dropped.
    func takeFocusRequest() -> FocusRequest? {
        guard let request = focusRequest else { return nil }
        focusRequest = nil
        return Date().timeIntervalSince(request.date) < Self.focusRequestLifetime ? request : nil
    }

    /// Opens a note in the notch, ready to type in, as opening a note from
    /// the notes list does in Windows.
    func showInNotch(_ id: UUID) {
        select(id)
        requestFocus(pointerIsOnNotch: false)
        NotificationCenter.default.post(name: .showStickyNotesInNotch, object: nil)
    }

    // MARK: - Saving

    /// Writes pending changes right away; called when the app quits.
    func flushSync() {
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedChanges else { return }
        hasUnsavedChanges = false
        let snapshot = document
        let store = store
        storageQueue.sync {
            do {
                try store.save(snapshot)
            } catch {
                Log.stickyNotes.error("Couldn't save sticky notes: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func scheduleSave() {
        guard didLoad, canSave else { return }
        hasUnsavedChanges = true
        guard saveTask == nil else { return }
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard let self, !Task.isCancelled else { return }
            self.saveTask = nil
            self.saveNow()
        }
    }

    private func saveNow() {
        guard hasUnsavedChanges else { return }
        hasUnsavedChanges = false
        let snapshot = document
        let store = store
        storageQueue.async {
            do {
                try store.save(snapshot)
            } catch {
                Log.stickyNotes.error("Couldn't save sticky notes: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
