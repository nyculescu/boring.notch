//
//  NotchDrop.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import AppKit
import Defaults

/// Where things dragged onto the notch go: the Shelf when it's enabled, as
/// upstream does, otherwise the Clipboard tab when clipboard history is on.
@MainActor
enum NotchDrop {
    static var target: NotchViews? {
        if Defaults[.boringShelf] {
            return .shelf
        }
        if Defaults[.clipboardHistoryEnabled] {
            return .clipboard
        }
        return nil
    }

    static func accept(_ providers: [NSItemProvider]) {
        switch target {
        case .shelf:
            ShelfStateViewModel.shared.load(providers)
        case .clipboard:
            ClipboardHistoryManager.shared.addDropped(providers)
        case .home, nil:
            break
        }
    }
}
