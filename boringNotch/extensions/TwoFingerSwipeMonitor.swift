//
//  TwoFingerSwipeMonitor.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import AppKit
import Defaults
import SwiftUI

/// Watches two-finger swipes over the view it backs and reports a step to
/// the next or previous page, once per swipe. It follows the notch's
/// gesture settings: off with "Enable gestures", as far as "Gesture
/// sensitivity" asks, and in the fingers' direction when "Normalize gesture
/// direction" is on, like the media swipes (see PanGesture). Scroll events
/// pass through untouched, so a note's text still scrolls.
struct TwoFingerSwipeMonitor: NSViewRepresentable {
    let onSwipe: (TwoFingerSwipeTracker.Step) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.onSwipe = onSwipe
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class MonitorView: NSView {
        var onSwipe: ((TwoFingerSwipeTracker.Step) -> Void)?
        private var monitor: Any?
        private var tracker = TwoFingerSwipeTracker(threshold: 200)

        // Never takes a click meant for the view on top of it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            tracker.reset()
        }

        private func handle(_ event: NSEvent) {
            // Only fingers on a trackpad (or Magic Mouse) have a phase; wheel
            // clicks and the momentum after a flick don't take part.
            guard event.window === window, event.momentumPhase.isEmpty, !event.phase.isEmpty else { return }
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                tracker.reset()
            }
            guard event.phase.contains(.began) || event.phase.contains(.changed) else {
                tracker.reset()
                return
            }
            guard Defaults[.enableGestures], bounds.contains(convert(event.locationInWindow, from: nil)) else {
                return
            }
            tracker.threshold = Defaults[.gestureSensitivity]
            let direction: CGFloat = Defaults[.normalizeGestureDirection]
                ? (event.isDirectionInvertedFromDevice ? 1 : -1)
                : 1
            if let step = tracker.move(dx: event.scrollingDeltaX * direction, dy: event.scrollingDeltaY * direction) {
                onSwipe?(step)
            }
        }
    }
}
