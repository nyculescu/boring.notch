//
//  QuitRequestGuardTests.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  Which quit requests Boring Notch turns down: another app's, right after
//  one of its windows closed, the way Vorssaint's "Quit on close" sends one
//  when the Settings window closes.
//

import AppKit
import XCTest
@testable import boringNotch

final class QuitRequestGuardTests: XCTestCase {
    private let ownPID: pid_t = 4000
    private let vorssaint: pid_t = 85205
    private let closed = Date(timeIntervalSince1970: 1_800_000_000)

    private func refuses(
        _ request: QuitRequest,
        secondsAfterClose: TimeInterval?
    ) -> Bool {
        QuitRequestGuard.shouldRefuse(
            request,
            ownPID: ownPID,
            lastWindowClose: secondsAfterClose == nil ? nil : closed,
            now: closed.addingTimeInterval(secondsAfterClose ?? 0)
        )
    }

    func testRefusesAnotherAppsQuitRightAfterAWindowCloses() {
        let request = QuitRequest(senderPID: vorssaint, hasSystemReason: false)
        // Vorssaint 3.3.5 asks between 0.35 + 1.2 and 2.2 + 1.2 seconds after the close.
        for seconds in [0.0, 1.55, 3.4, 4.9] {
            XCTAssertTrue(refuses(request, secondsAfterClose: seconds), "\(seconds) s after the close")
        }
    }

    func testAllowsAQuitLongAfterTheWindowClosed() {
        let request = QuitRequest(senderPID: vorssaint, hasSystemReason: false)
        XCTAssertFalse(refuses(request, secondsAfterClose: QuitRequestGuard.windowCloseGracePeriod))
        XCTAssertFalse(refuses(request, secondsAfterClose: 60))
    }

    func testAllowsAQuitWhenNoWindowHasClosed() {
        XCTAssertFalse(refuses(QuitRequest(senderPID: vorssaint, hasSystemReason: false), secondsAfterClose: nil))
    }

    func testAlwaysAllowsLoggingOutRestartingAndShuttingDown() {
        XCTAssertFalse(refuses(QuitRequest(senderPID: 400, hasSystemReason: true), secondsAfterClose: 1))
    }

    func testAlwaysAllowsTheAppsOwnQuit() {
        XCTAssertFalse(refuses(QuitRequest(senderPID: ownPID, hasSystemReason: false), secondsAfterClose: 1))
    }

    func testAClockThatWentBackwardsRefusesNothing() {
        XCTAssertFalse(refuses(QuitRequest(senderPID: vorssaint, hasSystemReason: false), secondsAfterClose: -1))
    }

    // MARK: Reading the Apple Event

    private func fourCharCode(_ text: String) -> FourCharCode {
        text.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }

    private func appleEvent(
        _ eventClass: String,
        _ eventID: String,
        reason: String? = nil
    ) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: fourCharCode(eventClass),
            eventID: fourCharCode(eventID),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: ownPID),
            returnID: -1,
            transactionID: 0
        )
        if let reason {
            event.setAttribute(
                NSAppleEventDescriptor(enumCode: fourCharCode(reason)),
                forKeyword: AEKeyword(kAEQuitReason)
            )
        }
        return event
    }

    func testReadsAQuitEvent() {
        let request = QuitRequestGuard.quitRequest(from: appleEvent("aevt", "quit"), senderPID: vorssaint)
        XCTAssertEqual(request, QuitRequest(senderPID: vorssaint, hasSystemReason: false))
    }

    func testReadsWhyTheSystemIsQuittingApps() {
        let request = QuitRequestGuard.quitRequest(from: appleEvent("aevt", "quit", reason: "logo"), senderPID: 400)
        XCTAssertEqual(request?.hasSystemReason, true)
    }

    func testIgnoresOtherEventsAndEventsWithoutASender() {
        XCTAssertNil(QuitRequestGuard.quitRequest(from: appleEvent("aevt", "odoc"), senderPID: vorssaint))
        XCTAssertNil(QuitRequestGuard.quitRequest(from: appleEvent("aevt", "quit"), senderPID: nil))
        XCTAssertNil(QuitRequestGuard.quitRequest(from: appleEvent("aevt", "quit"), senderPID: 0))
        // A built event has no sender, so the real reader finds none either.
        XCTAssertNil(QuitRequestGuard.quitRequest(from: appleEvent("aevt", "quit")))
    }
}
