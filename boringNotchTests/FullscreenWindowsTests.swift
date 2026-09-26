//
//  FullscreenWindowsTests.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  Which screens a player covers with a window when it goes full screen
//  without a full-screen Space, the way VLC does by default.
//

import CoreGraphics
import XCTest
@testable import boringNotch

final class FullscreenWindowsTests: XCTestCase {
    private typealias Window = FullscreenWindows.Window

    private let vlc: pid_t = 38570
    private let builtIn = FullscreenWindows.Display(uuid: "BUILT-IN", bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
    private let external = FullscreenWindows.Display(uuid: "EXTERNAL", bounds: CGRect(x: 1512, y: 0, width: 2560, height: 1440))

    private func covered(_ windows: [Window]) -> Set<String> {
        FullscreenWindows.displays(coveredBy: vlc, windows: windows, displays: [builtIn, external])
    }

    func testAWindowFillingAScreenCoversIt() {
        XCTAssertEqual(covered([Window(ownerPID: vlc, layer: 0, bounds: builtIn.bounds)]), ["BUILT-IN"])
        XCTAssertEqual(covered([Window(ownerPID: vlc, layer: 0, bounds: external.bounds)]), ["EXTERNAL"])
    }

    func testAWindowAFractionOffStillCounts() {
        let bounds = builtIn.bounds.insetBy(dx: 0.5, dy: 0.5)
        XCTAssertEqual(covered([Window(ownerPID: vlc, layer: 0, bounds: bounds)]), ["BUILT-IN"])
    }

    func testAMaximizedWindowIsNotFullScreen() {
        // Zoomed windows stop at the menu bar (and the Dock).
        let zoomed = CGRect(x: 0, y: 33, width: 1512, height: 949)
        XCTAssertEqual(covered([Window(ownerPID: vlc, layer: 0, bounds: zoomed)]), [])
    }

    func testOnlyThePlayersWindowsCount() {
        XCTAssertEqual(covered([Window(ownerPID: 13335, layer: 0, bounds: builtIn.bounds)]), [])
    }

    func testDesktopAndScreenSaverLayersDoNotCount() {
        let desktop = Int(CGWindowLevelForKey(.desktopWindow))
        let screenSaver = Int(CGWindowLevelForKey(.screenSaverWindow))
        XCTAssertEqual(covered([Window(ownerPID: vlc, layer: desktop, bounds: builtIn.bounds)]), [])
        XCTAssertEqual(covered([Window(ownerPID: vlc, layer: screenSaver, bounds: builtIn.bounds)]), [])
    }

    func testFloatingAndOnTopVideoWindowsCount() {
        // VLC's "Float on Top" puts its video at the status level.
        for key in [CGWindowLevelKey.floatingWindow, .statusWindow] {
            let layer = Int(CGWindowLevelForKey(key))
            XCTAssertEqual(covered([Window(ownerPID: vlc, layer: layer, bounds: builtIn.bounds)]), ["BUILT-IN"], "layer \(layer)")
        }
    }
}
