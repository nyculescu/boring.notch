//
//  StickyNoteSwipeTracker.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import CoreGraphics

/// Turns a two-finger swipe across the note into at most one step to a
/// neighboring note. Only the fingers' travel counts: the caller leaves out
/// the momentum that follows a flick, so a flick never steps twice, and a
/// mostly vertical scroll (reading down a long note) never steps at all.
struct StickyNoteSwipeTracker {
    enum Step: Equatable {
        /// Fingers moving left push the note away, bringing in the next older one.
        case older
        /// Fingers moving right bring back the next newer note.
        case newer
    }

    /// How far the fingers must travel sideways, in scroll points.
    var threshold: CGFloat

    private var travelX: CGFloat = 0
    private var travelY: CGFloat = 0
    private var stepped = false

    init(threshold: CGFloat) {
        self.threshold = threshold
    }

    /// Call when fingers touch down, and when they lift.
    mutating func reset() {
        travelX = 0
        travelY = 0
        stepped = false
    }

    /// Adds the fingers' movement, positive to the right and down. Returns a
    /// step the moment the swipe first crosses the threshold, and nil for the
    /// rest of the gesture.
    mutating func move(dx: CGFloat, dy: CGFloat) -> Step? {
        travelX += dx
        travelY += dy
        guard !stepped, abs(travelX) >= threshold, abs(travelX) >= 2 * abs(travelY) else { return nil }
        stepped = true
        return travelX < 0 ? .older : .newer
    }
}
