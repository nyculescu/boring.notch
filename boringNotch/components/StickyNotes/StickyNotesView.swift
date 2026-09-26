//
//  StickyNotesView.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import AppKit
import Defaults
import SwiftUI

/// The Sticky Notes tab: the note you used last, filling the tab, written in
/// place. A band along its top holds + for a new note, the page dots, the
/// color swatches and the notes list; a two-finger swipe moves between notes.
struct StickyNotesView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var notes = StickyNotesManager.shared
    @Default(.compactMode) private var compactMode
    @State private var editor = EditorHandle()
    @State private var showsColors = false
    /// Where the next note comes in from: older notes from the right, newer
    /// ones from the left, as if the notes lay side by side, newest first.
    @State private var incomingEdge: Edge = .trailing
    @State private var bounceOffset: CGFloat = 0

    /// The text view on screen, so a request for the keyboard can reach it.
    private final class EditorHandle {
        weak var textView: NSTextView?
    }

    /// Up to this many notes show as dots; beyond it, as "3 / 12".
    private let maxDots = 8

    private var bandHeight: CGFloat { compactMode ? 18 : 24 }
    private var fontSize: CGFloat { compactMode ? 12 : 13 }
    private var textInset: NSSize { compactMode ? NSSize(width: 4, height: 3) : NSSize(width: 8, height: 6) }
    private var cornerRadius: CGFloat { compactMode ? 8 : 10 }

    var body: some View {
        ZStack {
            if let note = notes.currentNote {
                noteCard(note)
                    .id(note.id)
                    .transition(.push(from: incomingEdge))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: bounceOffset)
        // Keeps a note sliding in or out inside the tab.
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background(TwoFingerSwipeMonitor { step in move(step == .forward ? 1 : -1) })
        .onAppear { notes.ensureNote() }
        .onChange(of: notes.document.notes.isEmpty) { _, isEmpty in
            if isEmpty {
                notes.ensureNote()
            }
        }
        .onChange(of: notes.focusRequest?.id) { _, id in
            if id != nil, let textView = editor.textView, textView.window != nil {
                takeRequestedFocus(in: textView)
            }
        }
        .onDisappear {
            showsColors = false
            // Typing goes back to the app in front; the notch still closes
            // when the pointer leaves it (see NotchKeyboardFocus).
            NotchKeyboardFocus.shared.giveBack()
        }
    }

    // MARK: - Note

    private func noteCard(_ note: StickyNote) -> some View {
        VStack(spacing: 0) {
            band(for: note)
                .frame(height: bandHeight)
                .background(note.color.bandColor)
            ZStack(alignment: .topLeading) {
                StickyNoteEditor(
                    text: text(of: note),
                    fontSize: fontSize,
                    textColor: note.color.inkNSColor,
                    isDark: note.color.isDark,
                    textContainerInset: textInset,
                    onClick: { textView in
                        showsColors = false
                        NotchKeyboardFocus.shared.take(for: textView, in: textView.window, viewModel: vm, pointerIsOnNotch: true)
                    },
                    onAttach: { textView in editorAttached(textView) },
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

    private func band(for note: StickyNote) -> some View {
        HStack(spacing: 0) {
            NoteBandButton(icon: "plus", label: "New Note", size: bandHeight, ink: note.color.inkColor) {
                newNote(pointerIsOnNotch: true)
            }
            Spacer(minLength: 4)
            if showsColors {
                swatches(for: note)
                    .transition(.opacity)
            } else {
                pageIndicator(ink: note.color.inkColor)
                    .transition(.opacity)
            }
            Spacer(minLength: 4)
            NoteBandButton(
                icon: "paintpalette",
                label: "Note Color",
                size: bandHeight,
                ink: note.color.inkColor,
                isSelected: showsColors
            ) {
                withAnimation(.smooth(duration: 0.2)) { showsColors.toggle() }
            }
            NoteBandButton(icon: "list.bullet", label: "Notes List", size: bandHeight, ink: note.color.inkColor) {
                showsColors = false
                StickyNotesListWindowController.shared.show()
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
                    withAnimation(.smooth(duration: 0.2)) { showsColors = false }
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

    @ViewBuilder
    private func pageIndicator(ink: Color) -> some View {
        let count = notes.document.notes.count
        let index = notes.document.currentIndex ?? 0
        if count > maxDots {
            Text("\(index + 1) / \(count)")
                .font(.system(size: compactMode ? 9 : 10, weight: .medium).monospacedDigit())
                .foregroundStyle(ink.opacity(0.55))
        } else if count > 1 {
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { dot in
                    Button {
                        move(dot - index)
                    } label: {
                        Circle()
                            .fill(ink.opacity(dot == index ? 0.65 : 0.22))
                            .frame(width: 5, height: 5)
                            .frame(width: 10, height: bandHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Note \(index + 1) of \(count)"))
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
    /// end the note gives a small nudge instead.
    private func move(_ offset: Int) {
        guard offset != 0 else { return }
        showsColors = false
        // The edge is set first and the note changes on the next turn, so
        // the note leaving slides out on the same side the new one comes from.
        incomingEdge = offset > 0 ? .trailing : .leading
        DispatchQueue.main.async {
            let moved = withAnimation(.smooth(duration: 0.3)) {
                notes.selectNeighbor(offset)
            }
            if !moved {
                nudge(toward: offset)
            }
        }
    }

    private func newNote(pointerIsOnNotch: Bool) {
        showsColors = false
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

    /// A note that appears while the notch has the keyboard (a new note, or
    /// one swiped to while typing) takes it over, caret at the end; so does
    /// one asked to (+ or the notes list).
    private func editorAttached(_ textView: NSTextView) {
        editor.textView = textView
        DispatchQueue.main.async {
            guard editor.textView === textView, textView.window != nil else { return }
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
