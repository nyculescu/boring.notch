//
//  ClipboardItem.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import Foundation

/// One entry in the clipboard history. Only what's needed to preview the entry
/// and put it back on the pasteboard is kept, and only in memory.
struct ClipboardItem: Identifiable, Equatable {
    enum Content: Equatable {
        case text(String)
        case files([URL])
    }

    let id: UUID
    let content: Content
    let copiedAt: Date
    /// Bundle identifier of the app that was frontmost when the copy was noticed.
    let sourceBundleIdentifier: String?

    init(id: UUID = UUID(), content: Content, copiedAt: Date = Date(), sourceBundleIdentifier: String?) {
        self.id = id
        self.content = content
        self.copiedAt = copiedAt
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }

    /// Single-line preview: whitespace runs collapsed, capped so huge copies stay cheap to render.
    var previewText: String {
        switch content {
        case .text(let text):
            return text.prefix(300)
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
        case .files(let urls):
            let names = urls.map(\.lastPathComponent)
            guard let first = names.first else { return "" }
            return names.count > 1 ? "\(first) +\(names.count - 1)" : first
        }
    }
}
