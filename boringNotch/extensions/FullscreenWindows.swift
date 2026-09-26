//
//  FullscreenWindows.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  Full screen without a full-screen Space: players like VLC (by default)
//  go full screen by covering the screen with an ordinary window, which
//  Space-based detection never sees.
//

import CoreGraphics
import Foundation

enum FullscreenWindows {
    struct Window: Equatable {
        var ownerPID: pid_t
        var layer: Int
        /// In global display coordinates, like CGDisplayBounds.
        var bounds: CGRect
    }

    struct Display: Equatable {
        var uuid: String
        var bounds: CGRect
    }

    /// Window layers a player's video can be on: ordinary, floating, or VLC's
    /// "Float on Top" (the status level); not the desktop or a screen saver.
    /// Only the player's own windows are looked at, so system bars never count.
    static let playerLayers = 0..<Int(CGWindowLevelForKey(.screenSaverWindow))

    /// The displays one of `pid`'s windows covers entirely.
    static func displays(
        coveredBy pid: pid_t,
        windows: [Window],
        displays: [Display]
    ) -> Set<String> {
        var covered = Set<String>()
        for window in windows where window.ownerPID == pid && playerLayers.contains(window.layer) {
            // A point of slack for windows that round to a fraction off.
            let reach = window.bounds.insetBy(dx: -1, dy: -1)
            for display in displays where reach.contains(display.bounds) {
                covered.insert(display.uuid)
            }
        }
        return covered
    }

    /// The windows on screen now, without the desktop's.
    static func onScreen() -> [Window] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return (info as? [[String: Any]] ?? []).compactMap { entry in
            guard let owner = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsInfo = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
            else {
                return nil
            }
            return Window(ownerPID: owner, layer: entry[kCGWindowLayer as String] as? Int ?? 0, bounds: bounds)
        }
    }
}
