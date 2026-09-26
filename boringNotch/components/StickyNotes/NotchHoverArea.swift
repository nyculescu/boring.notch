//
//  NotchHoverArea.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import AppKit
import SwiftUI

/// Marks the area ContentView tracks hovering over, so code outside it can
/// tell where the notch really is: the open panel in either layout, whatever
/// its size. Put it in the background of the view that has the hover handler.
struct NotchHoverArea: NSViewRepresentable {
    func makeNSView(context: Context) -> MarkerView {
        MarkerView()
    }

    func updateNSView(_ nsView: MarkerView, context: Context) {}

    /// The hover area of the notch in `window`, in screen coordinates.
    @MainActor
    static func frame(in window: NSWindow) -> CGRect? {
        guard let marker = MarkerView.all.allObjects.first(where: { $0.window === window }) else { return nil }
        return window.convertToScreen(marker.convert(marker.bounds, to: nil))
    }

    final class MarkerView: NSView {
        static let all = NSHashTable<MarkerView>.weakObjects()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            Self.all.add(self)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        // A marker only: clicks and hovering belong to the notch.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
