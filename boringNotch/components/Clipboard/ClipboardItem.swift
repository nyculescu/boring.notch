//
//  ClipboardItem.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import Foundation

/// One entry in the clipboard history, as kept in memory and saved to disk.
struct ClipboardItem: Identifiable, Equatable, Codable {
    enum Content: Equatable, Codable {
        case text(String)
        case files([URL])
        case image(ClipboardImage)
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

    var image: ClipboardImage? {
        if case .image(let image) = content {
            return image
        }
        return nil
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
        case .image(let image):
            return "Image \(image.pixelWidth)×\(image.pixelHeight)"
        }
    }
}

/// A copied image. The pixels live in files named after `hash` (see
/// `ClipboardHistoryStore`), so identical copies share one file.
struct ClipboardImage: Codable {
    /// SHA-256 of the PNG data, as lowercase hex.
    let hash: String
    let pixelWidth: Int
    let pixelHeight: Int
}

extension ClipboardImage: Equatable {
    static func == (lhs: ClipboardImage, rhs: ClipboardImage) -> Bool {
        lhs.hash == rhs.hash
    }
}
