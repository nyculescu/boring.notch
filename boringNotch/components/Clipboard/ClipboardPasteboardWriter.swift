//
//  ClipboardPasteboardWriter.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import AppKit

/// Puts clipboard entries on a pasteboard. Called off the main thread.
enum ClipboardPasteboardWriter {
    static func write(text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// File URLs, so pasting in Finder copies the files, plus their paths as
    /// text, one per line, so pasting into a text field gives the paths.
    static func write(files urls: [URL], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    /// PNG, plus TIFF for older apps that only take that.
    static func write(png: Data, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}
