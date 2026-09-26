//
//  PlaybackStateTests.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  When a Now Playing update is still the same track, so that whether it's
//  a favorite (read from Apple Music) carries over instead of resetting.
//

import XCTest
@testable import boringNotch

final class PlaybackStateTests: XCTestCase {
    private func state(_ bundleIdentifier: String, _ title: String) -> PlaybackState {
        PlaybackState(bundleIdentifier: bundleIdentifier, title: title)
    }

    func testTheSameTrackIsTheSameItemWhateverElseChanges() {
        var playing = state("com.apple.Music", "Stick Season")
        playing.isFavorite = true
        var paused = playing
        paused.isPlaying = false
        paused.currentTime = 42
        paused.isFavorite = false
        XCTAssertTrue(paused.isSameItem(as: playing))
    }

    func testAnotherTitleOrAnotherAppIsAnotherItem() {
        let track = state("com.apple.Music", "Stick Season")
        XCTAssertFalse(state("com.apple.Music", "Blue Rose").isSameItem(as: track))
        XCTAssertFalse(state("com.brave.Browser", "Stick Season").isSameItem(as: track))
    }
}
