//
//  PlaybackHandoffScripts.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//
//  The AppleScript half of PlaybackHandoff. macOS only passes play/pause
//  commands to the Now Playing app, so an app that lost the slot has to be
//  paused through its own scripting: Apple Music and Spotify directly,
//  browsers by running a line of JavaScript in the tab that was playing.
//  None of these scripts ever launches an app.
//

import Foundation

enum PlaybackHandoffScripts {
    /// Pauses Music if it's playing. Returns {true, track ID} when it paused,
    /// {false, ""} otherwise.
    static let pauseAppleMusic = """
        if application "Music" is running then
            tell application "Music"
                if player state is playing then
                    set pausedTrackID to ""
                    try
                        set pausedTrackID to persistent ID of current track
                    end try
                    pause
                    return {true, pausedTrackID}
                end if
            end tell
        end if
        return {false, ""}
        """

    /// Plays Music again if it's still paused on `trackID`, so a track the
    /// listener picked in the meantime isn't started behind their back.
    static func resumeAppleMusic(trackID: String) -> String {
        """
        if application "Music" is running then
            tell application "Music"
                if player state is paused then
                    set currentTrackID to ""
                    try
                        set currentTrackID to persistent ID of current track
                    end try
                    if currentTrackID is "\(sanitizedTrackID(trackID))" then
                        play
                        return true
                    end if
                end if
            end tell
        end if
        return false
        """
    }

    /// The paused track's ID from `pauseAppleMusic`'s result, or nil when it
    /// didn't pause anything.
    static func pausedTrackID(from result: NSAppleEventDescriptor?) -> String? {
        guard let result,
              result.numberOfItems == 2,
              result.atIndex(1)?.booleanValue == true
        else {
            return nil
        }
        return result.atIndex(2)?.stringValue ?? ""
    }

    /// Persistent IDs are hexadecimal; anything else is dropped so an ID can
    /// never end the script's string early.
    static func sanitizedTrackID(_ trackID: String) -> String {
        String(trackID.filter(\.isHexDigit))
    }

    static let chromiumBrowsers: Set<String> = ["com.brave.Browser", "com.google.Chrome"]
    /// Safari's media shows up under its WebKit processes, and in private
    /// windows sometimes without Safari as their parent app.
    static let safariBundleIdentifiers: Set<String> = [
        "com.apple.Safari", "com.apple.WebKit.GPU", "com.apple.WebKit.WebContent"
    ]

    /// Pauses what a page is playing the way a listener would, so the site's
    /// player keeps up: its own Pause button next to the playing media, else
    /// the space bar. Pausing a media element directly leaves some players
    /// (Disney+) stuck showing Pause over a frozen picture, so that only
    /// happens when something is still playing a second later. Runs as one
    /// line, so no `//` comments.
    static let pauseMediaJavaScript = """
        (function () {
            var playing = Array.prototype.filter.call(document.querySelectorAll('video, audio'), function (media) {
                return !media.paused;
            });
            var isPause = function (control) {
                var label = (control.getAttribute('aria-label') || control.getAttribute('title') || '').trim();
                return /^pause(\\s*\\(.*\\))?$/i.test(label);
            };
            var pressed = [];
            var spaced = false;
            playing.forEach(function (media) {
                var control = null;
                for (var node = media.parentElement, depth = 0; node && !control && depth < 8; node = node.parentElement, depth++) {
                    control = Array.prototype.find.call(node.querySelectorAll('button, [role="button"]'), isPause) || null;
                }
                if (control) {
                    if (pressed.indexOf(control) < 0) { pressed.push(control); control.click(); }
                } else if (!spaced) {
                    spaced = true;
                    ['keydown', 'keyup'].forEach(function (type) {
                        media.dispatchEvent(new KeyboardEvent(type, {
                            key: ' ', code: 'Space', keyCode: 32, which: 32, bubbles: true, cancelable: true
                        }));
                    });
                }
            });
            setTimeout(function () {
                playing.forEach(function (media) { if (!media.paused) { media.pause(); } });
            }, 1000);
            return playing.length;
        })();
        """

    /// Starts again what a page had playing, the same way round as
    /// pauseMediaJavaScript: the site's own Play button next to the media it
    /// had got furthest into, else the space bar, and only if that media is
    /// still paused a second later, the media element itself. Runs as one
    /// line, so no `//` comments.
    static let playMediaJavaScript = """
        (function () {
            var paused = Array.prototype.filter.call(document.querySelectorAll('video, audio'), function (media) {
                return media.paused && !media.ended && media.readyState > 0;
            });
            if (paused.length === 0) { return 0; }
            paused.sort(function (a, b) { return b.currentTime - a.currentTime; });
            var media = paused[0];
            var isPlay = function (control) {
                var label = (control.getAttribute('aria-label') || control.getAttribute('title') || '').trim();
                return /^play(\\s*\\(.*\\))?$/i.test(label);
            };
            var control = null;
            for (var node = media.parentElement, depth = 0; node && !control && depth < 8; node = node.parentElement, depth++) {
                control = Array.prototype.find.call(node.querySelectorAll('button, [role="button"]'), isPlay) || null;
            }
            if (control) {
                control.click();
            } else {
                ['keydown', 'keyup'].forEach(function (type) {
                    media.dispatchEvent(new KeyboardEvent(type, {
                        key: ' ', code: 'Space', keyCode: 32, which: 32, bubbles: true, cancelable: true
                    }));
                });
            }
            setTimeout(function () {
                if (media.paused) {
                    var started = media.play();
                    if (started && started.catch) { started.catch(function () {}); }
                }
            }, 1000);
            return 1;
        })();
        """

    /// The script that pauses `player`, or nil when its app can't be paused
    /// with AppleScript (VLC gets raw Apple Events instead: see VLCRemote).
    /// Every script returns {number of things paused, error message or ""}.
    static func pause(_ player: PlaybackHandoffPolicy.Player) -> String? {
        if player.bundleIdentifier == MediaAppBundleID.spotify {
            return pauseSpotify
        }
        return tabScript(for: player, javaScript: pauseMediaJavaScript)
    }

    /// The script that starts `player`'s page playing again, or nil when it
    /// isn't a browser tab this can reach. Returns like pause(_:).
    static func play(_ player: PlaybackHandoffPolicy.Player) -> String? {
        tabScript(for: player, javaScript: playMediaJavaScript)
    }

    /// Runs `javaScript` in the tabs of `player`'s browser that show its title.
    private static func tabScript(for player: PlaybackHandoffPolicy.Player, javaScript: String) -> String? {
        let bundleIdentifier = player.bundleIdentifier
        // An empty title would match every tab.
        let title = player.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        if chromiumBrowsers.contains(bundleIdentifier) {
            return runInTabs(
                app: bundleIdentifier,
                titleProperty: "title",
                title: title,
                run: "execute tab tabIndex of browserWindow javascript \(quoted(javaScript))"
            )
        }
        if safariBundleIdentifiers.contains(bundleIdentifier) {
            return runInTabs(
                app: "com.apple.Safari",
                titleProperty: "name",
                title: title,
                run: "do JavaScript \(quoted(javaScript)) in tab tabIndex of browserWindow"
            )
        }
        return nil
    }

    /// How a pause script went: what it paused, and the last error it hit
    /// (a browser with JavaScript from Apple Events turned off, say).
    static func pauseOutcome(from result: NSAppleEventDescriptor?) -> (paused: Int, failure: String) {
        guard let result, result.numberOfItems == 2 else { return (0, "") }
        return (Int(result.atIndex(1)?.int32Value ?? 0), result.atIndex(2)?.stringValue ?? "")
    }

    /// `text` as an AppleScript string literal.
    static func quoted(_ text: String) -> String {
        let escaped = text.unicodeScalars.map { scalar -> String in
            switch scalar {
            case "\\": return "\\\\"
            case "\"": return "\\\""
            default: return CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
            }
        }
        return "\"" + escaped.joined() + "\""
    }

    private static let pauseSpotify = """
        if application id "com.spotify.client" is running then
            tell application id "com.spotify.client"
                if player state is playing then
                    pause
                    return {1, ""}
                end if
            end tell
        end if
        return {0, ""}
        """

    /// Runs `run` in each tab whose title contains `title`; titles are read
    /// a window at a time.
    private static func runInTabs(app: String, titleProperty: String, title: String, run: String) -> String {
        """
        set pausedTabs to 0
        set failure to ""
        if application id \(quoted(app)) is running then
            tell application id \(quoted(app))
                repeat with browserWindow in windows
                    try
                        set tabTitles to \(titleProperty) of every tab of browserWindow
                        repeat with tabIndex from 1 to count of tabTitles
                            if item tabIndex of tabTitles contains \(quoted(title)) then
                                try
                                    with timeout of 5 seconds
                                        \(run)
                                    end timeout
                                    set pausedTabs to pausedTabs + 1
                                on error errorMessage
                                    set failure to errorMessage
                                end try
                            end if
                        end repeat
                    end try
                end repeat
            end tell
        end if
        return {pausedTabs, failure}
        """
    }
}
