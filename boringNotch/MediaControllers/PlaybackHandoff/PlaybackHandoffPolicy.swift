//
//  PlaybackHandoffPolicy.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//
//  Decides what to pause when playback moves from one app to another. It
//  only sees the Now Playing stream and returns actions for PlaybackHandoff
//  to carry out, so it can be tested without any player running.
//

import Foundation

/// Keeps one player on the speakers: when an app starts playing, the one
/// that was playing before it is paused, whether that's Apple Music, a
/// YouTube video in Brave or a film in Safari. Apple Music can also be
/// brought back once the app that interrupted it stops, but only after a
/// pause made here, and never once it has played again for another reason.
///
/// macOS keeps one Now Playing app: the last one to start playing, which
/// keeps the slot while paused. An app that loses the slot while playing
/// goes on playing out of sight of the stream, so it's remembered until the
/// next app starts. Apple Music doesn't need remembering: it can be asked
/// directly whether it's playing.
struct PlaybackHandoffPolicy: Equatable {
    struct Settings: Equatable {
        var pausesOtherPlayers: Bool
        var resumesAppleMusic: Bool
    }

    /// An app's Now Playing item: which app, and the title it shows.
    struct Player: Equatable {
        var bundleIdentifier: String
        var title: String
    }

    enum Action: Equatable {
        case pauseAppleMusic
        /// Pause what `player` is playing: the tab showing its title, say.
        case pausePlayer(Player)
        case startResumeTimer
        case cancelResumeTimer
        /// Play Apple Music again, but only if it's still paused on this track.
        case resumeAppleMusic(trackID: String)
    }

    private(set) var nowPlaying: Player?
    private(set) var nowPlayingIsPlaying = false
    /// An app that lost Now Playing while it was playing.
    private(set) var displacedPlayer: Player?
    /// The Now Playing app while it's an app other than Apple Music that is playing.
    private(set) var otherPlayer: String?
    /// The track Apple Music was paused on here; "" when it had no ID.
    private(set) var pausedTrackID: String?
    private(set) var isPausing = false
    private(set) var isResumeTimerRunning = false

    mutating func nowPlayingChanged(
        bundleIdentifier: String,
        title: String,
        isPlaying: Bool,
        settings: Settings
    ) -> [Action] {
        handOff(to: bundleIdentifier, title: title, isPlaying: isPlaying, settings: settings)
            + appleMusicActions(bundleIdentifier: bundleIdentifier, isPlaying: isPlaying, settings: settings)
    }

    /// Reports how `.pauseAppleMusic` went: the ID of the track it paused, or
    /// nil when Apple Music wasn't playing.
    mutating func pauseFinished(pausedTrackID trackID: String?, settings: Settings) -> [Action] {
        guard isPausing else { return [] }
        isPausing = false
        pausedTrackID = trackID
        // The other app may have stopped while the pause was on its way.
        return otherPlayer == nil ? startResumeTimerIfNeeded(settings) : []
    }

    mutating func resumeTimerFired(settings: Settings) -> [Action] {
        guard isResumeTimerRunning else { return [] }
        isResumeTimerRunning = false
        guard settings.resumesAppleMusic, otherPlayer == nil, let trackID = pausedTrackID else {
            return []
        }
        pausedTrackID = nil
        return [.resumeAppleMusic(trackID: trackID)]
    }

    /// Forgets everything without resuming, for when Now Playing stops being
    /// the media source and there's no telling what plays any more.
    mutating func reset() -> [Action] {
        let actions = cancelResumeTimer()
        self = PlaybackHandoffPolicy()
        return actions
    }

    /// The player that was playing before this one started, if any.
    private mutating func handOff(
        to bundleIdentifier: String,
        title: String,
        isPlaying: Bool,
        settings: Settings
    ) -> [Action] {
        let previous = nowPlaying
        let previousWasPlaying = nowPlayingIsPlaying
        // The adapter reports an empty item between apps; that's no player.
        nowPlaying = bundleIdentifier.isEmpty ? nil : Player(bundleIdentifier: bundleIdentifier, title: title)
        nowPlayingIsPlaying = nowPlaying != nil && isPlaying

        if let previous, previousWasPlaying,
           previous.bundleIdentifier != bundleIdentifier,
           previous.bundleIdentifier != MediaAppBundleID.appleMusic {
            displacedPlayer = previous
        }
        if displacedPlayer?.bundleIdentifier == bundleIdentifier {
            displacedPlayer = nil
        }

        let keptPlaying = previousWasPlaying && previous?.bundleIdentifier == bundleIdentifier
        guard nowPlayingIsPlaying, !keptPlaying, settings.pausesOtherPlayers,
              let displaced = displacedPlayer
        else {
            return []
        }
        displacedPlayer = nil
        return [.pausePlayer(displaced)]
    }

    private mutating func appleMusicActions(
        bundleIdentifier: String,
        isPlaying: Bool,
        settings: Settings
    ) -> [Action] {
        let otherPlayerWasPlaying = otherPlayer != nil
        let isAppleMusic = bundleIdentifier == MediaAppBundleID.appleMusic
        let isOtherPlayer = !bundleIdentifier.isEmpty && !isAppleMusic
        otherPlayer = isOtherPlayer && isPlaying ? bundleIdentifier : nil

        if isAppleMusic && isPlaying {
            // Someone played Apple Music (or a resume landed): the pause
            // isn't ours to undo any more.
            pausedTrackID = nil
            return cancelResumeTimer()
        }

        switch (otherPlayerWasPlaying, otherPlayer != nil) {
        case (false, true):
            var actions = cancelResumeTimer()
            if settings.pausesOtherPlayers, pausedTrackID == nil, !isPausing {
                isPausing = true
                actions.append(.pauseAppleMusic)
            }
            return actions
        case (true, false):
            return startResumeTimerIfNeeded(settings)
        default:
            return []
        }
    }

    private mutating func startResumeTimerIfNeeded(_ settings: Settings) -> [Action] {
        guard settings.resumesAppleMusic, pausedTrackID != nil else { return [] }
        isResumeTimerRunning = true
        return [.startResumeTimer]
    }

    private mutating func cancelResumeTimer() -> [Action] {
        guard isResumeTimerRunning else { return [] }
        isResumeTimerRunning = false
        return [.cancelResumeTimer]
    }
}
