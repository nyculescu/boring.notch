//
//  StickyNoteSwipeTrackerTests.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//
//  A two-finger swipe steps one note at a time: left to older notes, right
//  to newer ones, never twice in one swipe, and never for vertical scrolling.
//

import XCTest
@testable import boringNotch

final class StickyNoteSwipeTrackerTests: XCTestCase {
    private var tracker = StickyNoteSwipeTracker(threshold: 200)

    /// Feeds a swipe in `count` equal movements and returns every step it produced.
    private func swipe(dx: CGFloat, dy: CGFloat = 0, in count: Int = 10) -> [StickyNoteSwipeTracker.Step] {
        (0..<count).compactMap { _ in tracker.move(dx: dx / CGFloat(count), dy: dy / CGFloat(count)) }
    }

    func testFingersMovingLeftStepToAnOlderNoteOnce() {
        XCTAssertEqual(swipe(dx: -600), [.older])
    }

    func testFingersMovingRightStepToANewerNote() {
        XCTAssertEqual(swipe(dx: 250), [.newer])
    }

    func testAShortSwipeDoesNothing() {
        XCTAssertEqual(swipe(dx: -150), [])
    }

    func testScrollingDownALongNoteNeverSteps() {
        XCTAssertEqual(swipe(dx: -300, dy: 400), [])
    }

    func testASlightlySlantedSwipeStillSteps() {
        XCTAssertEqual(swipe(dx: -300, dy: 60), [.older])
    }

    func testGoingBackAndForthCancelsOut() {
        XCTAssertEqual(swipe(dx: 150), [])
        XCTAssertEqual(swipe(dx: -150), [])
    }

    func testTheNextSwipeStepsAgain() {
        XCTAssertEqual(swipe(dx: -300), [.older])
        tracker.reset()
        XCTAssertEqual(swipe(dx: -300), [.older])
    }

    func testFollowsTheSensitivitySetting() {
        tracker.threshold = 100
        XCTAssertEqual(swipe(dx: -120), [.older])
    }
}
