//
//  QuitRequestGuard.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  Closing a window never quits Boring Notch, even when another app asks
//  it to. Utilities that quit apps when their last window closes (Vorssaint's
//  "Quit on close", for one) see Boring Notch as an ordinary app while its
//  Settings window is open, since it shows in the Dock then, and send it a
//  quit request a moment after that window closes. The notch is still
//  there, so that request is turned down.
//

import AppKit

/// A request to quit, as far as the guard needs to know it.
struct QuitRequest: Equatable {
    /// The process that sent the quit Apple Event.
    var senderPID: pid_t
    /// Log out, restart and shut down say why they quit apps.
    var hasSystemReason: Bool
}

enum QuitRequestGuard {
    /// How long after one of the app's windows closes a quit from another
    /// app is taken for a reaction to that close. Vorssaint's comes at most
    /// about 3.4 seconds after the close.
    static let windowCloseGracePeriod: TimeInterval = 5

    /// Whether to turn `request` down: it comes from another app, not from
    /// logging out, restarting or shutting down, and right after a window closed.
    static func shouldRefuse(
        _ request: QuitRequest,
        ownPID: pid_t,
        lastWindowClose: Date?,
        now: Date
    ) -> Bool {
        guard request.senderPID != ownPID, !request.hasSystemReason, let lastWindowClose else {
            return false
        }
        let elapsed = now.timeIntervalSince(lastWindowClose)
        return elapsed >= 0 && elapsed < windowCloseGracePeriod
    }

    /// The quit Apple Event being handled right now, or nil when the app is
    /// quitting some other way (its own Quit, Command-Q) or the event names
    /// no sender.
    static func currentQuitRequest() -> QuitRequest? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return nil }
        return quitRequest(from: event)
    }

    static func quitRequest(from event: NSAppleEventDescriptor) -> QuitRequest? {
        quitRequest(
            from: event,
            senderPID: event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        )
    }

    /// `senderPID` is the event's sender attribute, which macOS stamps on an
    /// event when it delivers it; one built in place can't carry it.
    static func quitRequest(from event: NSAppleEventDescriptor, senderPID: Int32?) -> QuitRequest? {
        guard event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEQuitApplication),
              let sender = senderPID,
              sender > 0
        else {
            return nil
        }
        let reason = AEKeyword(kAEQuitReason)
        let hasSystemReason = event.attributeDescriptor(forKeyword: reason) != nil
            || event.paramDescriptor(forKeyword: reason) != nil
        return QuitRequest(senderPID: sender, hasSystemReason: hasSystemReason)
    }
}
