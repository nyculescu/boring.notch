//
//  MediaPlayerSnapshot.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  One app registered with macOS Now Playing, as the nowplaying-players
//  helper reports it (nowplaying-players/NowPlayingPlayers.m), for the Media
//  tab's pages of other players.
//

import Foundation

struct MediaPlayerSnapshot: Identifiable, Equatable, Sendable {
    /// "<bundle ID>:<pid>": one per running player.
    let id: String
    let bundleIdentifier: String
    /// Safari's media plays in a WebKit process; this is Safari.
    let parentBundleIdentifier: String?
    let processIdentifier: Int32
    let displayName: String?
    let isPlaying: Bool
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let elapsedTime: Double
    /// When `elapsedTime` was measured.
    let timestamp: Date?
    let playbackRate: Double
    let artworkIdentifier: String?

    /// The app the page stands for: Safari rather than its WebKit process.
    var appBundleIdentifier: String {
        parentBundleIdentifier ?? bundleIdentifier
    }

    /// Where playback is at `date`, moving on while it plays.
    func position(at date: Date) -> Double {
        var position = elapsedTime
        if isPlaying, playbackRate > 0, let timestamp {
            position += date.timeIntervalSince(timestamp) * playbackRate
        }
        return duration > 0 ? min(max(position, 0), duration) : max(position, 0)
    }
}

/// One line from the helper: every player, and which one macOS elected.
struct NowPlayingPlayersMessage: Decodable, Sendable {
    struct Player: Decodable, Sendable {
        let id: String
        let bundleIdentifier: String
        let parentBundleIdentifier: String?
        let processIdentifier: Int32
        let displayName: String?
        let isPlaying: Bool
        let title: String?
        let artist: String?
        let album: String?
        let duration: Double?
        let elapsedTime: Double?
        /// Seconds since 1970.
        let timestamp: Double?
        let playbackRate: Double?
        let artworkIdentifier: String?
        /// Base64, only when this player's artwork changed.
        let artworkData: String?

        var snapshot: MediaPlayerSnapshot {
            MediaPlayerSnapshot(
                id: id,
                bundleIdentifier: bundleIdentifier,
                parentBundleIdentifier: parentBundleIdentifier,
                processIdentifier: processIdentifier,
                displayName: displayName,
                isPlaying: isPlaying,
                title: title ?? "",
                artist: artist ?? "",
                album: album ?? "",
                duration: duration ?? 0,
                elapsedTime: elapsedTime ?? 0,
                timestamp: timestamp.map { Date(timeIntervalSince1970: $0) },
                playbackRate: playbackRate ?? 0,
                artworkIdentifier: artworkIdentifier
            )
        }
    }

    /// The process macOS elected as the Now Playing app, if any.
    let elected: Int32?
    let players: [Player]
}
