//
//  ClipboardDropReader.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import AppKit
import UniformTypeIdentifiers

/// Turns what was dropped on the notch into one clipboard entry: every dropped
/// file and folder together, or else an image, a link or text.
///
/// Item providers aren't Sendable, so they stay on the main actor; their load
/// callbacks hand back plain URLs, strings and data, and image conversion runs
/// off the main thread on those.
@MainActor
enum ClipboardDropReader {
    enum Dropped {
        case content(ClipboardItem.Content)
        case image(ClipboardImageData)
    }

    static func read(_ providers: [NSItemProvider]) async -> Dropped? {
        var files: [URL] = []
        for provider in providers {
            if let url = await loadURL(from: provider, type: .fileURL), url.isFileURL {
                files.append(url)
            }
        }
        if !files.isEmpty {
            return .content(.files(files))
        }
        guard let provider = providers.first else { return nil }
        // An image before its link: dragging a picture off a web page carries both.
        if let image = await loadImage(from: provider) {
            return .image(image)
        }
        if let url = await loadURL(from: provider, type: .url), url.scheme != nil {
            return .content(.text(url.absoluteString))
        }
        for type in [UTType.utf8PlainText, .plainText] {
            if let text = await loadText(from: provider, type: type), !text.allSatisfy(\.isWhitespace) {
                return .content(.text(text))
            }
        }
        return nil
    }

    // MARK: - Loading

    private static func loadURL(from provider: NSItemProvider, type: UTType) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                continuation.resume(returning: url(from: item))
            }
        }
    }

    private static func loadText(from provider: NSItemProvider, type: UTType) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                continuation.resume(returning: text(from: item))
            }
        }
    }

    private static func loadImage(from provider: NSItemProvider) async -> ClipboardImageData? {
        // Ask for the concrete format the drop carries (PNG, JPEG…), not the abstract image type.
        guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
            return nil
        }
        let data: Data? = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else { return nil }
        return await Task.detached(priority: .userInitiated) { pngImage(from: data) }.value
    }

    // MARK: - Converting (any thread)

    /// File and web URLs arrive as URLs, as URL strings, as plain paths or,
    /// from some apps, as bookmark data.
    nonisolated private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        var string = item as? String
        if let data = item as? Data {
            string = String(data: data, encoding: .utf8)
            if string.flatMap({ URL(string: $0) }) == nil && string?.hasPrefix("/") != true {
                var isStale = false
                return try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &isStale)
            }
        }
        guard let string else { return nil }
        return string.hasPrefix("/") ? URL(fileURLWithPath: string) : URL(string: string)
    }

    nonisolated private static func text(from item: NSSecureCoding?) -> String? {
        if let text = item as? String {
            return text
        }
        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    nonisolated private static func pngImage(from data: Data) -> ClipboardImageData? {
        guard data.count <= ClipboardPasteboardReader.maxSourceImageBytes,
              let rep = NSBitmapImageRep(data: data),
              rep.pixelsWide > 0, rep.pixelsHigh > 0,
              let png = rep.representation(using: .png, properties: [:]),
              png.count <= ClipboardPasteboardReader.maxImageBytes
        else {
            return nil
        }
        return ClipboardImageData(png: png, pixelWidth: rep.pixelsWide, pixelHeight: rep.pixelsHigh)
    }
}
