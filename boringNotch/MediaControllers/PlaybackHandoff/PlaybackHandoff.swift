//
//  PlaybackHandoff.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//
//  Carries out PlaybackHandoffPolicy. MusicManager feeds it every Now
//  Playing update; it pauses the player that was interrupted over
//  AppleScript, resumes Apple Music when asked to, and owns the resume delay.
//

import AppKit
import Defaults

@MainActor
final class PlaybackHandoff {
    /// How long the other app has to stay stopped before Apple Music comes
    /// back: short, so the music follows right on, but not instant, so the
    /// empty item Now Playing reports between two videos doesn't bring the
    /// music back in between.
    static let resumeDelay: Duration = .seconds(1)

    private var policy = PlaybackHandoffPolicy()
    private var resumeTask: Task<Void, Never>?

    private var settings: PlaybackHandoffPolicy.Settings {
        .init(
            pausesOtherPlayers: Defaults[.pauseOtherPlayers],
            resumesAppleMusic: Defaults[.resumeAppleMusicAfterOtherPlayers]
        )
    }

    func nowPlayingChanged(bundleIdentifier: String, title: String, isPlaying: Bool) {
        perform(policy.nowPlayingChanged(
            bundleIdentifier: bundleIdentifier,
            title: title,
            isPlaying: isPlaying,
            settings: settings
        ))
    }

    /// For when Now Playing stops being the media source: a pause made
    /// earlier is forgotten rather than resumed at a guess.
    func reset() {
        perform(policy.reset())
    }

    private func perform(_ actions: [PlaybackHandoffPolicy.Action]) {
        let newPlayer = policy.nowPlaying?.bundleIdentifier ?? "another app"
        for action in actions {
            switch action {
            case .pauseAppleMusic:
                Task { await pauseAppleMusic(for: newPlayer) }
            case .pausePlayer(let player):
                Task { await pause(player, for: newPlayer) }
            case .startResumeTimer:
                startResumeTimer()
            case .cancelResumeTimer:
                resumeTask?.cancel()
                resumeTask = nil
            case .resumeAppleMusic(let trackID):
                Task { await resumeAppleMusic(trackID: trackID) }
            }
        }
    }

    private func pauseAppleMusic(for newPlayer: String) async {
        var pausedTrackID: String?
        if Self.isRunning(MediaAppBundleID.appleMusic) {
            do {
                let result = try await AppleScriptHelper.execute(PlaybackHandoffScripts.pauseAppleMusic)
                pausedTrackID = PlaybackHandoffScripts.pausedTrackID(from: result)
            } catch {
                Log.music.error("Couldn't pause Apple Music: \(error.localizedDescription, privacy: .public)")
            }
        }
        if pausedTrackID != nil {
            Log.music.notice("Paused Apple Music: \(newPlayer, privacy: .public) started playing")
        }
        perform(policy.pauseFinished(pausedTrackID: pausedTrackID, settings: settings))
    }

    private func pause(_ player: PlaybackHandoffPolicy.Player, for newPlayer: String) async {
        let app = player.bundleIdentifier
        guard let script = PlaybackHandoffScripts.pause(player) else {
            Log.music.info("Can't pause \(app, privacy: .public): it has no way to be scripted")
            return
        }
        do {
            let outcome = PlaybackHandoffScripts.pauseOutcome(
                from: try await AppleScriptHelper.execute(script)
            )
            if outcome.paused > 0 {
                Log.music.notice("Paused \(app, privacy: .public): \(newPlayer, privacy: .public) started playing")
            } else if !outcome.failure.isEmpty {
                // Most likely "Allow JavaScript from Apple Events" is off in the browser.
                Log.music.error("Couldn't pause \(app, privacy: .public): \(outcome.failure, privacy: .public)")
            } else {
                Log.music.info("Nothing to pause in \(app, privacy: .public) for \(player.title)")
            }
        } catch {
            Log.music.error("Couldn't pause \(app, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func resumeAppleMusic(trackID: String) async {
        guard Self.isRunning(MediaAppBundleID.appleMusic) else { return }
        do {
            let result = try await AppleScriptHelper.execute(
                PlaybackHandoffScripts.resumeAppleMusic(trackID: trackID)
            )
            if result?.booleanValue == true {
                Log.music.notice("Resumed Apple Music")
            }
        } catch {
            Log.music.error("Couldn't resume Apple Music: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startResumeTimer() {
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.resumeDelay)
            guard !Task.isCancelled, let self else { return }
            self.resumeTask = nil
            self.perform(self.policy.resumeTimerFired(settings: self.settings))
        }
    }

    private static func isRunning(_ bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}
