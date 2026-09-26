//
//  ClipboardSettingsView.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import Defaults
import SwiftUI

struct ClipboardSettingsView: View {
    @Default(.clipboardHistoryEnabled) private var clipboardHistoryEnabled
    @Default(.clipboardHistoryLimit) private var clipboardHistoryLimit
    @ObservedObject private var clipboard = ClipboardHistoryManager.shared

    private let limitOptions = [5, 10, 20, 30]

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .clipboardHistoryEnabled) {
                    Text("Enable clipboard history")
                }
                Picker("Items to keep", selection: $clipboardHistoryLimit) {
                    ForEach(limitOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .disabled(!clipboardHistoryEnabled)
                HStack {
                    Text("History")
                    Spacer()
                    Button("Clear History") {
                        clipboard.clear()
                    }
                    .disabled(clipboard.items.isEmpty)
                }
            } header: {
                Text("General")
            } footer: {
                footnote("Text, images (screenshots included) and files are recorded; items that password managers mark as confidential never are. History is saved on this Mac, outside backups, and stays when you quit, restart or turn it off. Clear History deletes it.")
            }

            Section {
                HStack {
                    Text("Paste from Other Apps")
                    Spacer()
                    Button("Open Privacy Settings") {
                        ClipboardHistoryManager.openPrivacySettings()
                    }
                }
            } header: {
                Text("Permission")
            } footer: {
                footnote("macOS can ask before an app reads what other apps copied. Allow Boring Notch in Privacy & Security → Paste from Other Apps so history works without prompts, then relaunch Boring Notch.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Clipboard")
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.secondary)
            .font(.caption)
    }
}
