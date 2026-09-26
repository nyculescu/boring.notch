//
//  ClipboardView.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import AppKit
import SwiftUI

struct ClipboardView: View {
    @ObservedObject private var clipboard = ClipboardHistoryManager.shared
    @State private var copiedItemID: UUID?
    @State private var copiedResetTask: Task<Void, Never>?

    /// Five columns by two rows fits the default ten entries without scrolling.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        Group {
            if clipboard.isAccessDenied {
                message(icon: "hand.raised", text: "Boring Notch isn't allowed to read the clipboard", showsSettingsButton: true)
            } else if clipboard.items.isEmpty {
                message(icon: "doc.on.clipboard", text: "Copied text, images and files will appear here", showsSettingsButton: false)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(clipboard.items) { item in
                            ClipboardItemCell(
                                item: item,
                                thumbnail: item.image.flatMap { clipboard.thumbnail(for: $0) },
                                isCopied: item.id == copiedItemID
                            )
                                .onTapGesture { copy(item) }
                                .contextMenu { contextMenu(for: item) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { clipboard.checkNow() }
    }

    private func copy(_ item: ClipboardItem) {
        withAnimation(.smooth) {
            clipboard.copy(item)
            copiedItemID = item.id
        }
        copiedResetTask?.cancel()
        copiedResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { copiedItemID = nil }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ClipboardItem) -> some View {
        Button("Copy") { copy(item) }
        Button("Remove from History") {
            withAnimation(.smooth) { clipboard.remove(item) }
        }
        Divider()
        Button("Clear History") {
            withAnimation(.smooth) { clipboard.clear() }
        }
    }

    private func message(icon: String, text: LocalizedStringKey, showsSettingsButton: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.gray)
                .imageScale(.large)
            Text(text)
                .foregroundStyle(.gray)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.medium)
            if showsSettingsButton {
                Button("Open Privacy Settings") {
                    ClipboardHistoryManager.openPrivacySettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

private struct ClipboardItemCell: View {
    let item: ClipboardItem
    let thumbnail: NSImage?
    let isCopied: Bool
    @State private var isHovering = false

    private let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: 4) {
                if let icon = ClipboardAppIcon.icon(for: item.sourceBundleIdentifier) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 12, height: 12)
                }
                // A fixed format, not a live-updating relative date: no redraw timer.
                Text(item.copiedAt, format: .relative(presentation: .named, unitsStyle: .narrow))
                    .lineLimit(1)
            }
            .font(.system(size: 9))
            .foregroundStyle(.gray)
        }
        .padding(6)
        .frame(height: 54)
        .background(shape.fill(Color.white.opacity(isHovering ? 0.16 : 0.08)))
        .overlay {
            if isCopied {
                shape
                    .fill(Color.black.opacity(0.6))
                    .overlay {
                        Label("Copied", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .transition(.opacity)
            }
        }
        .contentShape(shape)
        .onHover { isHovering = $0 }
        .help(item.previewText)
    }

    @ViewBuilder
    private var preview: some View {
        switch item.content {
        case .text:
            previewLabel
        case .files(let urls):
            HStack(alignment: .top, spacing: 5) {
                if let first = urls.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                previewLabel
            }
        case .image:
            if let thumbnail {
                // Fill the preview area, cropping instead of letterboxing.
                Color.clear
                    .overlay {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Label(item.previewText, systemImage: "photo")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
            }
        }
    }

    private var previewLabel: some View {
        Text(item.previewText)
            .font(.system(size: 11))
            .foregroundStyle(.white)
            .lineLimit(2)
    }
}

/// App icons for the "copied from" badge, looked up once per app.
@MainActor
private enum ClipboardAppIcon {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier else { return nil }
        if let cached = cache[bundleIdentifier] {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleIdentifier] = icon
        return icon
    }
}
