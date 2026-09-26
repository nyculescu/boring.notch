// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
//  StickyNoteEditor.swift
//  boringNotch
//
//  Adapted by Catalin Niculescu on 2026-09-25 from PlainTextEditor in
//  Vorssaint (https://github.com/vorssaint/vorssaint-utils,
//  Sources/Vorssaint/UI/PlainTextEditor.swift): the plain-text AppKit text
//  view, its binding and the undo reset on outside changes come from there.
//  Added here: the click that lends the notch the keyboard, the note's
//  colors, an undo history per note, Escape and the editing shortcuts.
//

import AppKit
import SwiftUI

/// A note's text, edited in place: an AppKit text view configured as a pure
/// plain-text surface, with undo. SwiftUI's TextEditor can't be told to take
/// the keyboard from inside the notch, which only lends it on a click.
struct StickyNoteEditor: NSViewRepresentable {
    /// Shared with the placeholder, which is positioned from the same numbers
    /// as the first line of text.
    static let lineFragmentPadding: CGFloat = 5

    @Binding var text: String
    var fontSize: CGFloat
    var textColor: NSColor
    /// The notch is always dark, but a note is light paper unless it's
    /// charcoal: the selection and scroller follow the paper, not the notch.
    var isDark: Bool
    var textContainerInset: NSSize
    /// Called on a click in the text, before the click itself is handled:
    /// the moment to take the keyboard.
    var onClick: (NSTextView) -> Void
    /// Called when the text view lands in a window, to hand it the keyboard
    /// if it should have it (a new note, or one moved to while typing).
    var onAttach: (NSTextView) -> Void
    var onEscape: () -> Void
    var onNewNote: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        // Sideways swipes move between notes; the text never scrolls sideways.
        scrollView.horizontalScrollElasticity = .none

        let contentSize = scrollView.contentSize
        let textView = StickyNoteTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = Self.lineFragmentPadding

        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        scrollView.documentView = textView
        configure(textView, in: scrollView)
        textView.string = text
        // Delegate last: assigning .string posts a selection notification
        // synchronously, and makeNSView runs inside SwiftUI's update pass,
        // where writing state is undefined behavior.
        textView.delegate = context.coordinator
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = nsView.documentView as? StickyNoteTextView else { return }
        configure(textView, in: nsView)
        guard textView.string != text, !textView.hasMarkedText() else { return }
        // Setting .string posts a selection notification, and answering it
        // here would write state from inside a view update.
        context.coordinator.isApplyingExternalText = true
        textView.string = text
        context.coordinator.isApplyingExternalText = false
        // Undo entries recorded against the old text would resurrect it, or
        // throw a range exception, if replayed.
        context.coordinator.undoManager.removeAllActions()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    /// Appearance and callbacks, applied on every update: a note's color can
    /// change while it's open.
    private func configure(_ textView: StickyNoteTextView, in scrollView: NSScrollView) {
        let font = NSFont.systemFont(ofSize: fontSize)
        if textView.font != font {
            textView.font = font
        }
        if textView.textColor != textColor {
            textView.textColor = textColor
            textView.insertionPointColor = textColor
        }
        // On the scroll view, so its scroller shows on the note too.
        let appearance: NSAppearance.Name = isDark ? .darkAqua : .aqua
        if scrollView.appearance?.name != appearance {
            scrollView.appearance = NSAppearance(named: appearance)
        }
        if textView.textContainerInset != textContainerInset {
            textView.textContainerInset = textContainerInset
        }
        textView.onClick = onClick
        textView.onAttach = onAttach
        textView.onEscape = onEscape
        textView.onNewNote = onNewNote
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isApplyingExternalText = false
        /// One per note: undoing in one note never replays another note's
        /// typing, as the window's shared undo manager would.
        let undoManager = UndoManager()

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText, let textView = notification.object as? NSTextView else { return }
            let current = textView.string
            if text.wrappedValue != current {
                text.wrappedValue = current
            }
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }
    }
}

final class StickyNoteTextView: NSTextView {
    var onClick: ((NSTextView) -> Void)?
    var onAttach: ((NSTextView) -> Void)?
    var onEscape: (() -> Void)?
    var onNewNote: (() -> Void)?

    // The notch isn't key before the first click, and that click should
    // place the caret, not just take the keyboard.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?(self)
        super.mouseDown(with: event)
    }

    // So Cut, Copy and Paste in the context menu reach this note.
    override func rightMouseDown(with event: NSEvent) {
        onClick?(self)
        super.rightMouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            onAttach?(self)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    /// The editing shortcuts are answered here, not left to the Edit menu,
    /// whose key equivalents Boring Notch, an app without a menu bar, can't
    /// count on reaching. Cmd-N starts a note, as Ctrl-N does in Windows.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (modifiers, key) {
        case ([.command], "n"):
            onNewNote?()
        case ([.command], "x"):
            cut(nil)
        case ([.command], "c"):
            copy(nil)
        case ([.command], "v"):
            paste(nil)
        case ([.command], "a"):
            selectAll(nil)
        case ([.command], "z"):
            if undoManager?.canUndo == true {
                undoManager?.undo()
            }
        case ([.command, .shift], "z"):
            if undoManager?.canRedo == true {
                undoManager?.redo()
            }
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
