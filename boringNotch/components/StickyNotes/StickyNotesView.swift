//
//  StickyNotesView.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import AppKit
import Defaults
import SwiftUI

/// The Sticky Notes tab: the notes you used last, written in place. The
/// full-size notch shows two side by side, compact mode one filling the tab.
/// A band along each note's top holds + for a new note, the page dots, the
/// color swatches and the notes list; a two-finger swipe moves between notes.
struct StickyNotesView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var notes = StickyNotesManager.shared
    @Default(.compactMode) private var compactMode
    @Default(.stickyNotesWritingTools) private var allowsWritingTools
    @State private var editors = EditorHandles()
    /// The note whose band shows the color swatches.
    @State private var colorsNoteID: UUID?
    /// The two notes on screen in the full-size notch. They stay put while
    /// you write, though writing makes a note the newest; the next time the
    /// tab shows, the two written in last are side by side again.
    @State private var pairIDs: [UUID] = []
    /// Where the next note comes in from: older notes from the right, newer
    /// ones from the left, as if the notes lay side by side, newest first.
    @State private var incomingEdge: Edge = .trailing
    @State private var bounceOffset: CGFloat = 0

    /// The text views on screen, by note, so a request for the keyboard can
    /// reach the right one.
    @MainActor
    private final class EditorHandles {
        private let textViews = NSMapTable<NSUUID, NSTextView>.strongToWeakObjects()

        subscript(id: UUID?) -> NSTextView? {
            guard let id, let textView = textViews.object(forKey: id as NSUUID), textView.window != nil else { return nil }
            return textView
        }

        func register(_ textView: NSTextView, for id: UUID) {
            textViews.setObject(textView, forKey: id as NSUUID)
        }
    }

    /// Which of the band's controls a note shows. Side by side, the notes
    /// share them out: + and the page dots on the left, the notes list on
    /// the right, and each its own colors.
    private struct BandControls {
        var newNote = true
        var pages = true
        var list = true

        static let all = BandControls()
        static let leading = BandControls(list: false)
        static let trailing = BandControls(newNote: false, pages: false)
    }

    /// Up to this many notes show as dots; beyond it, as "3 / 12".
    private let maxDots = 8

    private var bandHeight: CGFloat { compactMode ? 18 : 24 }
    private var fontSize: CGFloat { compactMode ? 12 : 13 }
    private var textInset: NSSize { compactMode ? NSSize(width: 4, height: 3) : NSSize(width: 8, height: 6) }
    private var cornerRadius: CGFloat { compactMode ? 8 : 10 }
    private let cardSpacing: CGFloat = 8

    /// The notes on screen, newest-shown first.
    private var shownNotes: [StickyNote] {
        guard !compactMode else { return notes.currentNote.map { [$0] } ?? [] }
        let pair = pairIDs.compactMap { id in notes.document.notes.first { $0.id == id } }
        return pair.isEmpty ? notes.document.currentPair : pair
    }

    var body: some View {
        let shown = shownNotes
        // Compact mode's single note slides over the one leaving; side by
        // side, the note that stays slides across to make room.
        let layout = compactMode ? AnyLayout(ZStackLayout()) : AnyLayout(HStackLayout(spacing: cardSpacing))
        layout {
            ForEach(Array(shown.enumerated()), id: \.element.id) { position, note in
                noteCard(note, controls: controls(at: position, of: shown.count))
                    .transition(.push(from: incomingEdge))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: bounceOffset)
        // Keeps a note sliding in or out inside the tab.
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background(TwoFingerSwipeMonitor { step in move(step == .forward ? 1 : -1) })
        .onAppear {
            notes.ensureNote()
            pairIDs = notes.document.currentPair.map(\.id)
        }
        .onChange(of: notes.document) { _, document in
            if document.notes.isEmpty {
                notes.ensureNote()
            } else if !compactMode, document.pairNeedsRefresh(pairIDs) {
                withAnimation(.smooth(duration: 0.3)) {
                    pairIDs = document.currentPair.map(\.id)
                }
            }
        }
        .onChange(of: compactMode) { _, _ in
            pairIDs = notes.document.currentPair.map(\.id)
        }
        .onChange(of: notes.focusRequest?.id) { _, id in
            if id != nil, let textView = editors[notes.currentNote?.id] {
                takeRequestedFocus(in: textView)
            }
        }
        .onDisappear {
            colorsNoteID = nil
            // Typing goes back to the app in front; the notch still closes
            // when the pointer leaves it (see NotchKeyboardFocus).
            NotchKeyboardFocus.shared.giveBack()
        }
    }

    private func controls(at position: Int, of count: Int) -> BandControls {
        guard count > 1 else { return .all }
        return position == 0 ? .leading : .trailing
    }

    // MARK: - Note

    private func noteCard(_ note: StickyNote, controls: BandControls) -> some View {
        VStack(spacing: 0) {
            band(for: note, controls: controls)
                .frame(height: bandHeight)
                .background(note.color.bandColor)
            ZStack(alignment: .topLeading) {
                StickyNoteEditor(
                    text: text(of: note),
                    fontSize: fontSize,
                    textColor: note.color.inkNSColor,
                    isDark: note.color.isDark,
                    textContainerInset: textInset,
                    allowsWritingTools: allowsWritingTools,
                    onClick: { textView in
                        colorsNoteID = nil
                        NotchKeyboardFocus.shared.take(for: textView, in: textView.window, viewModel: vm, pointerIsOnNotch: true)
                    },
                    onAttach: { textView in editorAttached(textView, for: note.id) },
                    onEscape: { NotchKeyboardFocus.shared.closeNotch() },
                    onNewNote: { newNote(pointerIsOnNotch: false) }
                )
                if note.text.isEmpty {
                    Text("Take a note…")
                        .font(.system(size: fontSize))
                        .foregroundStyle(note.color.inkColor.opacity(0.4))
                        .padding(.leading, textInset.width + StickyNoteEditor.lineFragmentPadding)
                        .padding(.top, textInset.height)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .background(note.color.paperColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Next Note") { move(1) }
        .accessibilityAction(named: "Previous Note") { move(-1) }
    }

    private func band(for note: StickyNote, controls: BandControls) -> some View {
        HStack(spacing: 0) {
            if controls.newNote {
                NoteBandButton(icon: "plus", label: "New Note", size: bandHeight, ink: note.color.inkColor) {
                    newNote(pointerIsOnNotch: true)
                }
            }
            Spacer(minLength: 4)
            if colorsNoteID == note.id {
                swatches(for: note)
                    .transition(.opacity)
            } else if controls.pages {
                pageIndicator(ink: note.color.inkColor)
                    .transition(.opacity)
            }
            Spacer(minLength: 4)
            NoteBandButton(
                icon: "paintpalette",
                label: "Note Color",
                size: bandHeight,
                ink: note.color.inkColor,
                isSelected: colorsNoteID == note.id
            ) {
                withAnimation(.smooth(duration: 0.2)) {
                    colorsNoteID = colorsNoteID == note.id ? nil : note.id
                }
            }
            if controls.list {
                NoteBandButton(icon: "list.bullet", label: "Notes List", size: bandHeight, ink: note.color.inkColor) {
                    colorsNoteID = nil
                    StickyNotesListWindowController.shared.show()
                }
            }
        }
        .padding(.horizontal, compactMode ? 2 : 4)
    }

    private func swatches(for note: StickyNote) -> some View {
        let size: CGFloat = compactMode ? 11 : 14
        return HStack(spacing: compactMode ? 4 : 6) {
            ForEach(StickyNoteColor.allCases, id: \.self) { color in
                Button {
                    notes.setColor(color, of: note.id)
                    withAnimation(.smooth(duration: 0.2)) { colorsNoteID = nil }
                } label: {
                    Circle()
                        .fill(color.bandColor)
                        .overlay(Circle().strokeBorder(note.color.inkColor.opacity(0.3), lineWidth: 1))
                        .overlay {
                            if color == note.color {
                                Image(systemName: "checkmark")
                                    .font(.system(size: size * 0.55, weight: .bold))
                                    .foregroundStyle(color.inkColor)
                            }
                        }
                        .frame(width: size, height: size)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(color.name)
                .accessibilityLabel(Text(color.name))
                .accessibilityAddTraits(color == note.color ? .isSelected : [])
            }
        }
    }

    /// One dot per note, lit for the notes on screen.
    @ViewBuilder
    private func pageIndicator(ink: Color) -> some View {
        let all = notes.document.notes
        let count = all.count
        let shown = shownNotes.compactMap { note in all.firstIndex { $0.id == note.id } }.sorted()
        if count > maxDots, let first = shown.first, let last = shown.last {
            Group {
                if first == last {
                    Text("\(first + 1) / \(count)")
                } else {
                    Text("\(first + 1)–\(last + 1) / \(count)")
                }
            }
                .font(.system(size: compactMode ? 9 : 10, weight: .medium).monospacedDigit())
                .foregroundStyle(ink.opacity(0.55))
        } else if count > shown.count, let first = shown.first, let last = shown.last {
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { dot in
                    Button {
                        jump(to: dot)
                    } label: {
                        Circle()
                            .fill(ink.opacity(shown.contains(dot) ? 0.65 : 0.22))
                            .frame(width: 5, height: 5)
                            .frame(width: 10, height: bandHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(first == last
                ? Text("Note \(first + 1) of \(count)")
                : Text("Notes \(first + 1) to \(last + 1) of \(count)"))
        }
    }

    private func text(of note: StickyNote) -> Binding<String> {
        Binding(
            // A note deleted from the notes list keeps its text while it slides out.
            get: { notes.document.notes.first { $0.id == note.id }?.text ?? note.text },
            set: { notes.updateText($0, of: note.id) }
        )
    }

    // MARK: - Moving between notes

    /// Moves `offset` notes along: positive toward older notes. At either
    /// end the notes give a small nudge instead.
    private func move(_ offset: Int) {
        guard offset != 0 else { return }
        colorsNoteID = nil
        // The edge is set first and the notes change on the next turn, so
        // the note leaving slides out on the same side the new one comes from.
        incomingEdge = offset > 0 ? .trailing : .leading
        if compactMode {
            DispatchQueue.main.async {
                let moved = withAnimation(.smooth(duration: 0.3)) {
                    notes.selectNeighbor(offset)
                }
                if !moved {
                    nudge(toward: offset)
                }
            }
        } else if let pair = notes.document.neighborPair(of: shownNotes.map(\.id), offset: offset) {
            DispatchQueue.main.async { show(pair) }
        } else {
            nudge(toward: offset)
        }
    }

    /// A page dot: that note, with the next older one beside it in the full-size notch.
    private func jump(to index: Int) {
        guard let first = shownNotes.first.flatMap({ note in notes.document.notes.firstIndex { $0.id == note.id } }),
              index != first
        else {
            return
        }
        if compactMode {
            move(index - first)
            return
        }
        colorsNoteID = nil
        incomingEdge = index > first ? .trailing : .leading
        let pair = notes.document.pair(startingAt: index)
        DispatchQueue.main.async { show(pair) }
    }

    /// Puts `pair` on screen, the newer of the two as the note showing. If
    /// the notch has the keyboard, it goes to that note.
    private func show(_ pair: [StickyNote]) {
        guard let newest = pair.first else { return }
        withAnimation(.smooth(duration: 0.3)) {
            pairIDs = pair.map(\.id)
            notes.select(newest.id)
        }
        DispatchQueue.main.async {
            guard let textView = editors[newest.id],
                  NotchKeyboardFocus.shared.hasKeyboard(in: textView.window),
                  textView.window?.firstResponder !== textView
            else {
                return
            }
            takeKeyboard(in: textView, pointerIsOnNotch: false)
        }
    }

    private func newNote(pointerIsOnNotch: Bool) {
        colorsNoteID = nil
        // The new note is the newest, so it comes in from the left.
        incomingEdge = .leading
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.3)) {
                notes.createNote()
            }
            notes.requestFocus(pointerIsOnNotch: pointerIsOnNotch)
        }
    }

    private func nudge(toward offset: Int) {
        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.6)) {
            bounceOffset = offset > 0 ? -10 : 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.7)) {
                bounceOffset = 0
            }
        }
    }

    // MARK: - Keyboard

    /// The note showing, when it appears while the notch has the keyboard
    /// (a new note, or one swiped to while typing), takes it over, caret at
    /// the end; so does one asked to (+ or the notes list). The note beside
    /// it waits for a click.
    private func editorAttached(_ textView: NSTextView, for id: UUID) {
        editors.register(textView, for: id)
        DispatchQueue.main.async {
            guard editors[id] === textView, notes.currentNote?.id == id else { return }
            if notes.focusRequest != nil {
                takeRequestedFocus(in: textView)
            } else if NotchKeyboardFocus.shared.hasKeyboard(in: textView.window) {
                takeKeyboard(in: textView, pointerIsOnNotch: false)
            }
        }
    }

    private func takeRequestedFocus(in textView: NSTextView) {
        guard let request = notes.takeFocusRequest() else { return }
        takeKeyboard(in: textView, pointerIsOnNotch: request.pointerIsOnNotch)
    }

    private func takeKeyboard(in textView: NSTextView, pointerIsOnNotch: Bool) {
        let focus = NotchKeyboardFocus.shared
        guard focus.take(for: textView, in: textView.window, viewModel: vm, pointerIsOnNotch: pointerIsOnNotch) else { return }
        let end = NSRange(location: (textView.string as NSString).length, length: 0)
        textView.setSelectedRange(end)
        textView.scrollRangeToVisible(end)
    }
}

/// An icon button on the note's band, lit up under the pointer.
private struct NoteBandButton: View {
    let icon: String
    let label: LocalizedStringKey
    let size: CGFloat
    let ink: Color
    var isSelected = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(ink.opacity(isSelected || isHovering ? 0.9 : 0.6))
                .frame(width: size + 2, height: size)
                .background {
                    if isSelected || isHovering {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(ink.opacity(0.1))
                            .padding(2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(Text(label))
    }
}
