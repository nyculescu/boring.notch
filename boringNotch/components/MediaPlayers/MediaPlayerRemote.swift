//
//  MediaPlayerRemote.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  What the controls on another player's page do. macOS only passes play,
//  pause and skip to the Now Playing app, so these go to the app itself, by
//  the route MediaPlayerRoute picks: AppleScript for Music and Spotify,
//  Apple Events for VLC (VLCRemote), and JavaScript in the tab for Brave,
//  Chrome and Safari (PlaybackHandoffScripts). Once a player starts, it
//  becomes the Now Playing app and the live page takes over, with every
//  control.
//

import AppKit

@MainActor
enum MediaPlayerRemote {
    static func supports(_ command: MediaPlayerCommand, for player: MediaPlayerSnapshot) -> Bool {
        MediaPlayerRoute(player: player)?.supports(command) ?? false
    }

    static func perform(_ command: MediaPlayerCommand, on player: MediaPlayerSnapshot) {
        guard let route = MediaPlayerRoute(player: player), route.supports(command) else { return }
        let app = player.appBundleIdentifier
        Log.music.notice("Player page: \(String(describing: command), privacy: .public) for \(app, privacy: .public)")
        Task {
            switch route {
            case .music, .spotify:
                if let script = route.appleScript(command) {
                    await runAppleScript(script, app: player.appBundleIdentifier)
                }
            case .vlc:
                await sendToVLC(command)
            case .browser:
                await togglePage(of: player)
            }
            NowPlayingPlayersService.shared.refresh(after: .milliseconds(600))
        }
    }

    private static func runAppleScript(_ script: String, app bundleIdentifier: String) async {
        // Never launch an app that has quit since its page was drawn.
        guard isRunning(bundleIdentifier) else { return }
        do {
            try await AppleScriptHelper.executeVoid(script)
        } catch {
            Log.music.error("Couldn't control \(bundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func sendToVLC(_ command: MediaPlayerCommand) async {
        guard isRunning(MediaAppBundleID.vlc) else { return }
        let vlcCommand: VLCRemote.Command = switch command {
        case .togglePlay: .togglePlay
        case .previous: .previous
        case .next: .next
        }
        do {
            try await Task.detached(priority: .userInitiated) {
                try VLCRemote.send(vlcCommand)
            }.value
        } catch {
            Log.music.error("Couldn't control VLC: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func togglePage(of player: MediaPlayerSnapshot) async {
        let page = PlaybackHandoffPolicy.Player(bundleIdentifier: player.bundleIdentifier, title: player.title)
        guard let script = player.isPlaying ? PlaybackHandoffScripts.pause(page) : PlaybackHandoffScripts.play(page) else {
            return
        }
        do {
            let outcome = PlaybackHandoffScripts.pauseOutcome(from: try await AppleScriptHelper.execute(script))
            if outcome.paused == 0, !outcome.failure.isEmpty {
                // Most likely "Allow JavaScript from Apple Events" is off in the browser.
                Log.music.error("Couldn't control \(player.appBundleIdentifier, privacy: .public): \(outcome.failure, privacy: .public)")
            }
        } catch {
            Log.music.error("Couldn't control \(player.appBundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func isRunning(_ bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}
