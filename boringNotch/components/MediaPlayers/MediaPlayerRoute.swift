//
//  MediaPlayerRoute.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  How the notch reaches a player that isn't the Now Playing app, and what
//  that player can take from it. MediaPlayerRemote does the sending.
//

import Foundation

enum MediaPlayerCommand {
    case togglePlay
    case previous
    case next
}

enum MediaPlayerRoute: Equatable {
    /// AppleScript, with its own play/pause and skip.
    case music
    case spotify
    /// Raw Apple Events (VLCRemote).
    case vlc
    /// JavaScript in the tab that shows the player's title (Brave, Chrome,
    /// Safari), which can play and pause what the page has but not skip.
    case browser

    init?(player: MediaPlayerSnapshot) {
        switch player.appBundleIdentifier {
        case MediaAppBundleID.appleMusic:
            self = .music
        case MediaAppBundleID.spotify:
            self = .spotify
        case MediaAppBundleID.vlc:
            self = .vlc
        default:
            let isBrowser = PlaybackHandoffScripts.chromiumBrowsers.contains(player.bundleIdentifier)
                || PlaybackHandoffScripts.safariBundleIdentifiers.contains(player.bundleIdentifier)
            // The tab is found by its title.
            guard isBrowser, !player.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            self = .browser
        }
    }

    func supports(_ command: MediaPlayerCommand) -> Bool {
        self == .browser ? command == .togglePlay : true
    }

    /// The AppleScript for Music or Spotify; nil for the other routes.
    func appleScript(_ command: MediaPlayerCommand) -> String? {
        let app: String
        switch self {
        case .music: app = MediaAppBundleID.appleMusic
        case .spotify: app = MediaAppBundleID.spotify
        case .vlc, .browser: return nil
        }
        let verb = switch command {
        case .togglePlay: "playpause"
        case .previous: "previous track"
        case .next: "next track"
        }
        return "tell application id \"\(app)\" to \(verb)"
    }
}
