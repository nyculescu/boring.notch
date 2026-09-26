//
//  StickyNoteColor+UI.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import AppKit
import SwiftUI

extension StickyNoteColor {
    var paperColor: Color { Color(nsColor: Self.nsColor(paper)) }
    var bandColor: Color { Color(nsColor: Self.nsColor(band)) }

    /// Text and icons on the note.
    var inkColor: Color { Color(nsColor: inkNSColor) }
    var inkNSColor: NSColor {
        isDark ? .white : NSColor(white: 0.12, alpha: 1)
    }

    var name: LocalizedStringKey {
        switch self {
        case .yellow: "Yellow"
        case .green: "Green"
        case .pink: "Pink"
        case .purple: "Purple"
        case .blue: "Blue"
        case .gray: "Gray"
        case .charcoal: "Charcoal"
        }
    }

    private static func nsColor(_ rgb: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
