//
//  ClipboardHistoryStore.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Saves clipboard history inside Boring Notch's container, so it survives
/// quitting, turning the feature off and restarting the Mac. The list goes to a
/// JSON file; each image goes to a PNG named after its hash, next to a small
/// thumbnail for the history grid. Not thread-safe: use it from one queue.
struct ClipboardHistoryStore {
    let directory: URL

    static let thumbnailMaxPixelSize = 320

    static var standard: ClipboardHistoryStore {
        let fileManager = FileManager.default
        let support = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        return ClipboardHistoryStore(
            directory: support
                .appendingPathComponent("boringNotch", isDirectory: true)
                .appendingPathComponent("Clipboard", isDirectory: true)
        )
    }

    var historyFile: URL { directory.appendingPathComponent("history.json") }
    var imagesDirectory: URL { directory.appendingPathComponent("Images", isDirectory: true) }

    func imageURL(for image: ClipboardImage) -> URL {
        imagesDirectory.appendingPathComponent("\(image.hash).png")
    }

    func thumbnailURL(for image: ClipboardImage) -> URL {
        imagesDirectory.appendingPathComponent("\(image.hash)-thumb.png")
    }

    /// The saved history, minus entries whose image files have gone missing.
    /// Also deletes image files no entry refers to (left behind by a crash).
    func load() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: historyFile),
              let saved = try? JSONDecoder().decode([ClipboardItem].self, from: data)
        else {
            removeImageFiles(notUsedBy: [])
            return []
        }
        let items = saved.filter { item in
            guard let image = item.image else { return true }
            return FileManager.default.fileExists(atPath: imageURL(for: image).path)
        }
        removeImageFiles(notUsedBy: items)
        return items
    }

    func save(_ items: [ClipboardItem]) throws {
        try prepareDirectories()
        try JSONEncoder().encode(items).write(to: historyFile, options: .atomic)
    }

    /// Writes an image and its thumbnail unless a copy with the same hash is already stored.
    func saveImage(_ data: ClipboardImageData) throws -> ClipboardImage {
        let hash = SHA256.hash(data: data.png).map { String(format: "%02x", $0) }.joined()
        let image = ClipboardImage(hash: hash, pixelWidth: data.pixelWidth, pixelHeight: data.pixelHeight)
        try prepareDirectories()
        if !FileManager.default.fileExists(atPath: imageURL(for: image).path) {
            try data.png.write(to: imageURL(for: image), options: .atomic)
        }
        if !FileManager.default.fileExists(atPath: thumbnailURL(for: image).path) {
            try writeThumbnail(of: data.png, to: thumbnailURL(for: image))
        }
        return image
    }

    func removeImageFiles(for hashes: Set<String>) {
        for hash in hashes {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent("\(hash).png"))
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent("\(hash)-thumb.png"))
        }
    }

    private func removeImageFiles(notUsedBy items: [ClipboardItem]) {
        let used = Set(items.compactMap { $0.image?.hash })
        let files = (try? FileManager.default.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let hash = file.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-thumb", with: "")
            if !used.contains(hash) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        // Copied content is nothing to restore from a backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = directory
        try? directory.setResourceValues(values)
    }

    private func writeThumbnail(of png: Data, to url: URL) throws {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.thumbnailMaxPixelSize
        ]
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
