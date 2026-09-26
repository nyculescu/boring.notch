//
//  NotchKeyboardFocus.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//
//  Modeled on how Vorssaint's Dynamic Island lends the keyboard to its
//  Scratchpad (https://github.com/vorssaint/vorssaint-utils, GPL-3.0-or-later):
//  the panel becomes key only while it's open and asked to, never activating
//  the app, and resigns key when it's done so typing goes back where it was.
//

import AppKit
import Combine

/// Lends the keyboard to a text view in the open notch, for as long as it's
/// being written in, and gives it back to the app in front afterwards.
///
/// The notch window can't become key by default, so that clicking it never
/// takes focus from the frontmost app (see
/// `BoringNotchSkyLightWindow.wantsKeyForTextInput`). Two things make lending
/// it more than flipping that flag:
///
/// - Taking or giving up key status makes SwiftUI report the pointer leaving
///   the notch while it's still there. Upstream's notification reply field
///   met this: the notch closed the moment the field was clicked. So once a
///   note has had the keyboard, the notch's own hover exits are held off (the
///   hold a popover uses, which explicit closes ignore) and the pointer is
///   checked against the notch's real area instead, closing the notch after
///   it has been away as long as a hover exit waits.
/// - Turning the flag off leaves the window key, and keystrokes kept going to
///   the closed notch instead of the app in front. `resignKey()` hands them
///   back.
@MainActor
final class NotchKeyboardFocus {
    static let shared = NotchKeyboardFocus()

    /// How often the pointer is checked while the notch is held open.
    private static let checkInterval: TimeInterval = 0.1
    /// Matches ContentView's hoverExitDelayMilliseconds.
    private static let exitDelay: TimeInterval = 0.35

    private weak var window: BoringNotchSkyLightWindow?
    private weak var viewModel: BoringViewModel?
    private var timer: Timer?
    private var outsideSince: Date?
    /// False when the notch opened from elsewhere (the notes list) and the
    /// pointer hasn't been on it since: it isn't leaving what it never visited.
    private var pointerHasVisited = false
    private var isMenuTracking = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var notchStateCancellable: AnyCancellable?

    private init() {}

    /// Whether a text view in `window` has the keyboard.
    func hasKeyboard(in window: NSWindow?) -> Bool {
        guard let window, window === self.window else { return false }
        return window.isKeyWindow && self.window?.wantsKeyForTextInput == true
    }

    /// True from the moment a note takes the keyboard until the notch closes:
    /// the notch then closes when the pointer leaves it, not on a timer.
    var holdsNotchOpen: Bool {
        timer != nil
    }

    /// Makes the notch key with `responder` taking the keystrokes.
    /// `pointerIsOnNotch` is false when the notch was opened from somewhere
    /// else, so it stays open until the pointer has been on it and left.
    @discardableResult
    func take(for responder: NSResponder, in window: NSWindow?, viewModel: BoringViewModel, pointerIsOnNotch: Bool) -> Bool {
        guard let window = window as? BoringNotchSkyLightWindow, viewModel.notchState == .open else { return false }
        if window !== self.window {
            end()
        }
        self.window = window
        self.viewModel = viewModel
        pointerHasVisited = pointerHasVisited || pointerIsOnNotch
        // Held before the key change, so the hover exit it causes finds the hold in place.
        viewModel.isPopoverActive = true
        startWatching()
        window.wantsKeyForTextInput = true
        window.makeKey()
        window.makeFirstResponder(responder)
        return window.isKeyWindow
    }

    /// Gives the keyboard back to the app in front, and keeps holding the
    /// notch open until the pointer leaves it or it closes.
    func giveBack() {
        guard let window else { return }
        window.wantsKeyForTextInput = false
        if window.isKeyWindow {
            window.resignKey()
        }
    }

    /// Gives the keyboard back and closes the notch, as Escape does.
    func closeNotch() {
        let viewModel = viewModel
        end()
        viewModel?.close()
    }

    /// Gives the keyboard back and lets the notch close normally again.
    func end() {
        giveBack()
        timer?.invalidate()
        timer = nil
        notchStateCancellable = nil
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        if viewModel?.notchState == .open {
            viewModel?.isPopoverActive = false
        }
        window = nil
        viewModel = nil
        outsideSince = nil
        pointerHasVisited = false
        isMenuTracking = false
    }

    // MARK: - Watching the pointer

    private func startWatching() {
        guard timer == nil, let window, let viewModel else { return }
        outsideSince = nil
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
        timer.tolerance = Self.checkInterval / 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Closed by a shortcut, a gesture or anything else: nothing left to hold.
        notchStateCancellable = viewModel.$notchState
            .sink { [weak self] state in
                guard state == .closed else { return }
                MainActor.assumeIsolated { self?.end() }
            }
        let center = NotificationCenter.default
        // Another app, or the notes list, took the keyboard back.
        observe(center, NSWindow.didResignKeyNotification, object: window) { $0.window?.wantsKeyForTextInput = false }
        // A menu (a note's context menu) keeps the notch while it's open.
        observe(center, NSMenu.didBeginTrackingNotification) { $0.isMenuTracking = true }
        observe(center, NSMenu.didEndTrackingNotification) { $0.isMenuTracking = false }
        // Never leave the keyboard with the notch across a lock or sleep.
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { $0.end() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification) { $0.end() }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        object: AnyObject? = nil,
        action: @escaping @MainActor @Sendable (NotchKeyboardFocus) -> Void
    ) {
        let observer = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, observer))
    }

    private func checkPointer() {
        guard let viewModel, viewModel.notchState == .open else {
            end()
            return
        }
        if isPointerOnNotch {
            pointerHasVisited = true
            outsideSince = nil
            return
        }
        // A menu open, or a button held (selecting text past the notch's
        // edge), keeps the notch until it's done.
        guard !isMenuTracking, NSEvent.pressedMouseButtons == 0 else {
            outsideSince = nil
            return
        }
        guard pointerHasVisited else {
            // Opened from the notes list: it stays while the note is written
            // in, and goes once the keyboard has gone elsewhere.
            if window?.wantsKeyForTextInput != true {
                closeNotch()
            }
            return
        }
        let now = Date()
        guard let outsideSince else {
            outsideSince = now
            return
        }
        if now.timeIntervalSince(outsideSince) >= Self.exitDelay {
            closeNotch()
        }
    }

    private var isPointerOnNotch: Bool {
        let point = NSEvent.mouseLocation
        if let window, let area = NotchHoverArea.frame(in: window) {
            // The pointer at the very top of the screen sits on the area's
            // upper edge, which contains(_:) leaves out.
            return area.insetBy(dx: 0, dy: -1).contains(point)
        }
        return viewModel?.isMouseHovering(position: point) ?? false
    }
}
