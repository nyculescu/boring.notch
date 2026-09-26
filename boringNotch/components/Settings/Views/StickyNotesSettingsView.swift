//
//  StickyNotesSettingsView.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import Defaults
import SwiftUI

struct StickyNotesSettingsView: View {
    @ObservedObject private var notes = StickyNotesManager.shared
    @State private var confirmsDeleteAll = false

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .stickyNotesEnabled) {
                    Text("Enable sticky notes")
                }
                HStack {
                    Text("Notes")
                    Spacer()
                    Button("Show Notes List") {
                        StickyNotesListWindowController.shared.show()
                    }
                    Button("Delete All…") {
                        confirmsDeleteAll = true
                    }
                    .disabled(notes.writtenNotes.isEmpty)
                }
            } header: {
                Text("General")
            } footer: {
                footnote("The Sticky Notes tab shows the note you used last. Click it to type: the notch keeps the keyboard until the pointer leaves it, and Escape closes it. + (or Command-N) starts a note in the same color, the palette changes a note's color, and a two-finger swipe moves between notes, newest first. Notes are saved on this Mac as you type, and stay when you quit, restart or turn this off.")
            }

            if #available(macOS 15.0, *) {
                Section {
                    Defaults.Toggle(key: .stickyNotesWritingTools) {
                        Text("Allow Writing Tools in notes")
                    }
                } header: {
                    Text("Writing Tools")
                } footer: {
                    footnote("Apple Intelligence's Writing Tools proofread and rewrite a note. Off, their button no longer pops up over the text you select, and they leave the note's right-click menu too.")
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Sticky Notes")
        .alert("Delete all notes?", isPresented: $confirmsDeleteAll) {
            Button("Delete All", role: .destructive) {
                notes.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every note is deleted. The notes list offers Undo for a few seconds.")
        }
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.secondary)
            .font(.caption)
    }
}
