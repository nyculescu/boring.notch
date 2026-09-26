//
//  StickyNotesListWindow.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import AppKit
import SwiftUI

/// The notes list, in a small window of its own, like Windows Sticky Notes'
/// Notes list. It leaves the activation policy alone (the Settings window
/// owns that), so the two can be open together.
@MainActor
final class StickyNotesListWindowController: NSWindowController, NSWindowDelegate {
    static let shared = StickyNotesListWindowController()

    private static let autosaveName = "StickyNotesList"

    private init() {
        let window = StickyNotesListWindow(
            // Five cards and the bar above them; more notes scroll.
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 516),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Sticky Notes")
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 260, height: 240)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: StickyNotesListView())
        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // An app without a menu bar stays active with no window to type in:
        // hand the keyboard back, unless Settings is still open.
        if SettingsWindowController.shared.window?.isVisible != true {
            NSApp.deactivate()
        }
    }
}

/// Closes on Cmd-W, which the app's menu doesn't offer.
private final class StickyNotesListWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct StickyNotesListView: View {
    @ObservedObject private var notes = StickyNotesManager.shared
    @State private var confirmsClearAll = false

    /// Five cards fit the window's default height, the rest scroll.
    static let cardHeight: CGFloat = 84

    var body: some View {
        let written = notes.writtenNotes
        VStack(spacing: 0) {
            HStack {
                Text(written.count == 1 ? "1 note" : "\(written.count) notes")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All", role: .destructive) {
                    confirmsClearAll = true
                }
                .disabled(written.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if written.isEmpty {
                emptyMessage
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 8) {
                        ForEach(written) { note in
                            StickyNoteCard(
                                note: note,
                                onOpen: { notes.showInNotch(note.id) },
                                onDelete: { withAnimation(.smooth) { notes.delete(note.id) } }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .padding(12)
                }
            }
            if !notes.recentlyDeleted.isEmpty {
                undoBar(count: notes.recentlyDeleted.count)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 260, minHeight: 240)
        .animation(.smooth, value: notes.recentlyDeleted.isEmpty)
        .alert("Delete all notes?", isPresented: $confirmsClearAll) {
            Button("Delete All", role: .destructive) {
                withAnimation(.smooth) { notes.deleteAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every note. You can bring them back for a few seconds with Undo.")
        }
    }

    private var emptyMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No notes yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Write one in the notch's Sticky Notes tab.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func undoBar(count: Int) -> some View {
        HStack {
            Text(count == 1 ? "Note deleted" : "\(count) notes deleted")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Undo") {
                withAnimation(.smooth) { notes.undoDelete() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// A note in the list: its colors, its first lines and when it last changed.
private struct StickyNoteCard: View {
    let note: StickyNote
    let onOpen: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    private let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            note.color.bandColor
                .frame(height: 5)
            HStack(alignment: .top, spacing: 6) {
                Text(note.previewText)
                    .font(.system(size: 12))
                    .foregroundStyle(note.color.inkColor)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .trailing, spacing: 4) {
                    Self.dateText(note.modifiedAt)
                        .font(.system(size: 10))
                        .foregroundStyle(note.color.inkColor.opacity(0.55))
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(note.color.inkColor.opacity(isHovering ? 0.75 : 0.35))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete Note")
                    .accessibilityLabel("Delete Note")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(height: StickyNotesListView.cardHeight, alignment: .top)
        .background(note.color.paperColor)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.black.opacity(isHovering ? 0.18 : 0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        .contentShape(shape)
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onOpen)
        .help("Open in the notch")
        .contextMenu {
            Button("Open in the Notch", action: onOpen)
            Button("Delete Note", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Delete Note", onDelete)
    }

    /// The time for a note changed today, the date otherwise, as the Windows list shows it.
    private static func dateText(_ date: Date) -> Text {
        if Calendar.current.isDateInToday(date) {
            return Text(date, format: .dateTime.hour().minute())
        }
        if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) {
            return Text(date, format: .dateTime.month(.abbreviated).day())
        }
        return Text(date, format: .dateTime.year().month(.abbreviated).day())
    }
}
