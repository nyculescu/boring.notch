//
//  TwoFingerSwipeTrackerTests.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//
//  A two-finger swipe steps one page at a time (a sticky note, a player):
//  left to the next, right back, never twice in one swipe, and never for
//  vertical scrolling.
//

import XCTest
@testable import boringNotch

final class TwoFingerSwipeTrackerTests: XCTestCase {
    private var tracker = TwoFingerSwipeTracker(threshold: 200)

    /// Feeds a swipe in `count` equal movements and returns every step it produced.
    private func swipe(dx: CGFloat, dy: CGFloat = 0, in count: Int = 10) -> [TwoFingerSwipeTracker.Step] {
        (0..<count).compactMap { _ in tracker.move(dx: dx / CGFloat(count), dy: dy / CGFloat(count)) }
    }

    func testFingersMovingLeftStepForwardOnce() {
        XCTAssertEqual(swipe(dx: -600), [.forward])
    }

    func testFingersMovingRightStepBack() {
        XCTAssertEqual(swipe(dx: 250), [.backward])
    }

    func testAShortSwipeDoesNothing() {
        XCTAssertEqual(swipe(dx: -150), [])
    }

    func testScrollingDownALongNoteNeverSteps() {
        XCTAssertEqual(swipe(dx: -300, dy: 400), [])
    }

    func testASlightlySlantedSwipeStillSteps() {
        XCTAssertEqual(swipe(dx: -300, dy: 60), [.forward])
    }

    func testGoingBackAndForthCancelsOut() {
        XCTAssertEqual(swipe(dx: 150), [])
        XCTAssertEqual(swipe(dx: -150), [])
    }

    func testTheNextSwipeStepsAgain() {
        XCTAssertEqual(swipe(dx: -300), [.forward])
        tracker.reset()
        XCTAssertEqual(swipe(dx: -300), [.forward])
    }

    func testFollowsTheSensitivitySetting() {
        tracker.threshold = 100
        XCTAssertEqual(swipe(dx: -120), [.forward])
    }
}
