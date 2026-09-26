//
//  VLCRemote.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  Controls VLC with raw Apple Events. VLC only has an old-style scripting
//  dictionary (.scriptSuite), which AppleScript can't load from inside the
//  sandbox: compiling `tell application "VLC"` crashed the app. The events
//  need no dictionary: VLC's `playing` property is 'AAPL', its `play`
//  command ('VLC#'/'VLC1') toggles between playing and paused, and `next`
//  and `previous` are 'VLC4' and 'VLC3'.
//

import Foundation

enum VLCRemote {
    static func fourCharCode(_ text: String) -> FourCharCode {
        text.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }

    /// `get playing`: VLC's `playing` property, which is only true while it plays.
    static func isPlayingEvent() -> NSAppleEventDescriptor {
        let event = appleEvent(eventClass: fourCharCode("core"), eventID: fourCharCode("getd"))
        let property = NSAppleEventDescriptor.record().coerce(toDescriptorType: fourCharCode("obj "))
            ?? NSAppleEventDescriptor.record()
        property.setDescriptor(NSAppleEventDescriptor(typeCode: fourCharCode("prop")), forKeyword: fourCharCode("want"))
        property.setDescriptor(NSAppleEventDescriptor(enumCode: fourCharCode("prop")), forKeyword: fourCharCode("form"))
        property.setDescriptor(NSAppleEventDescriptor(typeCode: fourCharCode("AAPL")), forKeyword: fourCharCode("seld"))
        property.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: fourCharCode("from"))
        event.setParam(property, forKeyword: fourCharCode("----"))
        return event
    }

    enum Command: String {
        /// `play`, which pauses VLC when it's playing.
        case togglePlay = "VLC1"
        case previous = "VLC3"
        case next = "VLC4"
    }

    static func event(_ command: Command) -> NSAppleEventDescriptor {
        appleEvent(eventClass: fourCharCode("VLC#"), eventID: fourCharCode(command.rawValue))
    }

    /// `play`, which pauses VLC when it's playing.
    static func toggleEvent() -> NSAppleEventDescriptor {
        event(.togglePlay)
    }

    /// Sends `command`. Blocks while VLC answers (or while macOS asks, the
    /// first time, whether Boring Notch may control VLC), so call it off the
    /// main thread.
    static func send(_ command: Command) throws {
        _ = try event(command).sendEvent(options: [.waitForReply, .canInteract], timeout: 30)
    }

    /// Pauses VLC if it's playing; true when it did. Blocks while VLC answers
    /// (or while macOS asks the listener, the first time, whether Boring Notch
    /// may control VLC), so call it off the main thread.
    static func pauseIfPlaying() throws -> Bool {
        let options: NSAppleEventDescriptor.SendOptions = [.waitForReply, .canInteract]
        let reply = try isPlayingEvent().sendEvent(options: options, timeout: 30)
        guard reply.paramDescriptor(forKeyword: fourCharCode("----"))?.booleanValue == true else {
            return false
        }
        _ = try toggleEvent().sendEvent(options: options, timeout: 30)
        return true
    }

    private static func appleEvent(eventClass: AEEventClass, eventID: AEEventID) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor.appleEvent(
            withEventClass: eventClass,
            eventID: eventID,
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: MediaAppBundleID.vlc),
            returnID: -1, // kAutoGenerateReturnID
            transactionID: 0 // kAnyTransactionID
        )
    }
}
