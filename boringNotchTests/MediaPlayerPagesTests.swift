//
//  MediaPlayerPagesTests.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  The Media tab's pages of other players: which players get one and in
//  what order, where a swipe lands, reading the helper's lines, and how each
//  app is reached from its page.
//

import Foundation
import XCTest
@testable import boringNotch

final class MediaPlayerPagesTests: XCTestCase {
    private let musicPID: Int32 = 66395
    private let bravePID: Int32 = 13335
    private let vlcPID: Int32 = 38570
    private let safariPID: Int32 = 9565

    private func player(
        _ bundleIdentifier: String,
        pid: Int32,
        parent: String? = nil,
        title: String,
        playing: Bool = false,
        elapsed: Double = 0,
        duration: Double = 200,
        timestamp: Date? = nil,
        rate: Double = 1
    ) -> MediaPlayerSnapshot {
        MediaPlayerSnapshot(
            id: "\(bundleIdentifier):\(pid)",
            bundleIdentifier: bundleIdentifier,
            parentBundleIdentifier: parent,
            processIdentifier: pid,
            displayName: nil,
            isPlaying: playing,
            title: title,
            artist: "",
            album: "",
            duration: duration,
            elapsedTime: elapsed,
            timestamp: timestamp,
            playbackRate: playing ? rate : 0,
            artworkIdentifier: nil
        )
    }

    private var music: MediaPlayerSnapshot { player(MediaAppBundleID.appleMusic, pid: musicPID, title: "Stick Season") }
    private var brave: MediaPlayerSnapshot { player("com.brave.Browser", pid: bravePID, title: "A video") }
    private var vlc: MediaPlayerSnapshot { player(MediaAppBundleID.vlc, pid: vlcPID, title: "A film.mkv") }
    private var safari: MediaPlayerSnapshot {
        player("com.apple.WebKit.GPU", pid: safariPID, parent: "com.apple.Safari", title: "Toy Story 5 | Disney+")
    }

    private let nothingLive = MediaPlayerLineup.LivePage(bundleIdentifier: nil, title: "")

    // MARK: - Lineup

    func testThePlayerTheLivePageShowsGetsNoOtherPage() {
        var lineup = MediaPlayerLineup()
        let live = MediaPlayerLineup.LivePage(bundleIdentifier: "com.brave.Browser", title: "A video")
        lineup.update(with: [music, brave, vlc], elected: bravePID, live: live)
        XCTAssertEqual(lineup.players.map(\.id), [music.id, vlc.id])
    }

    func testTheElectedAppIsTheLivePageEvenWhileItsTitleCatchesUp() {
        var lineup = MediaPlayerLineup()
        let live = MediaPlayerLineup.LivePage(bundleIdentifier: "com.brave.Browser", title: "The previous video")
        lineup.update(with: [music, brave], elected: bravePID, live: live)
        XCTAssertEqual(lineup.players.map(\.id), [music.id])
    }

    func testANewlyElectedAppHasAPageUntilTheLivePageCatchesUp() {
        // Music started from its page; the live page still shows Brave.
        var lineup = MediaPlayerLineup()
        let stale = MediaPlayerLineup.LivePage(bundleIdentifier: "com.brave.Browser", title: "A video")
        lineup.update(with: [music, brave], elected: musicPID, live: stale)
        XCTAssertEqual(lineup.players.map(\.id), [music.id], "Music isn't lost while the live page still shows Brave")

        let caughtUp = MediaPlayerLineup.LivePage(bundleIdentifier: MediaAppBundleID.appleMusic, title: "Stick Season")
        lineup.update(with: [music, brave], elected: musicPID, live: caughtUp)
        XCTAssertEqual(lineup.players.map(\.id), [brave.id])
    }

    func testPlayersWithNothingToShowGetNoPage() {
        var lineup = MediaPlayerLineup()
        let empty = player("com.apple.podcasts", pid: 4242, title: "  ")
        lineup.update(with: [music, empty], elected: nil, live: nothingLive)
        XCTAssertEqual(lineup.players.map(\.id), [music.id])
    }

    func testWhatTheLivePageShowsIsNotShownTwice() {
        var lineup = MediaPlayerLineup()
        let live = MediaPlayerLineup.LivePage(bundleIdentifier: "com.apple.Safari", title: safari.title)
        lineup.update(with: [safari, vlc], elected: nil, live: live)
        XCTAssertEqual(lineup.players.map(\.id), [vlc.id])
    }

    func testPlayersComeInTheOrderTheyTurnedUpUntilOneIsPlayed() {
        var lineup = MediaPlayerLineup()
        lineup.update(with: [music, brave, vlc], elected: nil, live: nothingLive)
        XCTAssertEqual(lineup.players.map(\.id), [music.id, brave.id, vlc.id])

        // VLC plays, then pauses: it moves to the front and stays there.
        let vlcPlaying = player(MediaAppBundleID.vlc, pid: vlcPID, title: "A film.mkv", playing: true)
        lineup.update(with: [music, brave, vlcPlaying], elected: nil, live: nothingLive)
        lineup.update(with: [music, brave, vlc], elected: nil, live: nothingLive)
        XCTAssertEqual(lineup.players.map(\.id), [vlc.id, music.id, brave.id])
    }

    func testTheMostRecentlyStartedComesFirst() {
        var lineup = MediaPlayerLineup()
        let musicPlaying = player(MediaAppBundleID.appleMusic, pid: musicPID, title: "Stick Season", playing: true)
        let bravePlaying = player("com.brave.Browser", pid: bravePID, title: "A video", playing: true)
        lineup.update(with: [musicPlaying, brave, vlc], elected: nil, live: nothingLive)
        lineup.update(with: [music, bravePlaying, vlc], elected: nil, live: nothingLive)
        lineup.update(with: [music, brave, vlc], elected: nil, live: nothingLive)
        XCTAssertEqual(lineup.players.map(\.id), [brave.id, music.id, vlc.id])
    }

    func testStillPlayingDoesNotReorder() {
        var lineup = MediaPlayerLineup()
        let musicPlaying = player(MediaAppBundleID.appleMusic, pid: musicPID, title: "Stick Season", playing: true)
        let vlcPlaying = player(MediaAppBundleID.vlc, pid: vlcPID, title: "A film.mkv", playing: true)
        lineup.update(with: [musicPlaying, vlc], elected: nil, live: nothingLive)
        lineup.update(with: [musicPlaying, vlcPlaying], elected: nil, live: nothingLive)
        // Music playing on (its next track, say) doesn't make it newer than VLC.
        lineup.update(with: [musicPlaying, vlcPlaying], elected: nil, live: nothingLive)
        XCTAssertEqual(lineup.players.map(\.id), [vlc.id, music.id])
    }

    func testAPlayerThatLeavesStartsOverWhenItComesBack() {
        var lineup = MediaPlayerLineup()
        let vlcPlaying = player(MediaAppBundleID.vlc, pid: vlcPID, title: "A film.mkv", playing: true)
        lineup.update(with: [music, vlcPlaying], elected: nil, live: nothingLive)
        lineup.update(with: [music], elected: nil, live: nothingLive)
        lineup.update(with: [music, vlc], elected: nil, live: nothingLive)
        XCTAssertEqual(lineup.players.map(\.id), [music.id, vlc.id])
    }

    // MARK: - Paging

    func testSwipesStepThroughThePagesAndStopAtTheEnds() {
        let ids = ["a", "b"]
        XCTAssertEqual(MediaPlayerPaging.move(.forward, from: nil, among: ids), .init(selection: "a"))
        XCTAssertEqual(MediaPlayerPaging.move(.forward, from: "a", among: ids), .init(selection: "b"))
        XCTAssertNil(MediaPlayerPaging.move(.forward, from: "b", among: ids))
        XCTAssertEqual(MediaPlayerPaging.move(.backward, from: "b", among: ids), .init(selection: "a"))
        XCTAssertEqual(MediaPlayerPaging.move(.backward, from: "a", among: ids), .init(selection: nil))
        XCTAssertNil(MediaPlayerPaging.move(.backward, from: nil, among: ids))
    }

    func testAPageThatWentAwayCountsAsTheLivePage() {
        XCTAssertEqual(MediaPlayerPaging.index(of: "gone", among: ["a"]), 0)
        XCTAssertEqual(MediaPlayerPaging.move(.forward, from: "gone", among: ["a"]), .init(selection: "a"))
        XCTAssertNil(MediaPlayerPaging.move(.forward, from: nil, among: []))
    }

    // MARK: - Snapshots

    func testPositionMovesOnOnlyWhilePlaying() {
        let start = Date(timeIntervalSince1970: 1_000)
        let playing = player("a", pid: 1, title: "t", playing: true, elapsed: 10, duration: 100, timestamp: start)
        XCTAssertEqual(playing.position(at: start.addingTimeInterval(5)), 15, accuracy: 0.001)
        XCTAssertEqual(playing.position(at: start.addingTimeInterval(500)), 100, "Never past the end")

        let paused = player("a", pid: 1, title: "t", elapsed: 10, duration: 100, timestamp: start)
        XCTAssertEqual(paused.position(at: start.addingTimeInterval(5)), 10)
    }

    func testSafariPagesStandForSafari() {
        XCTAssertEqual(safari.appBundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(vlc.appBundleIdentifier, MediaAppBundleID.vlc)
    }

    func testReadsAHelperLine() throws {
        let line = """
            {"elected":13335,"players":[{"id":"com.apple.Music:66395","bundleIdentifier":"com.apple.Music",\
            "parentBundleIdentifier":null,"processIdentifier":66395,"displayName":"Music","isPlaying":false,\
            "title":"First Class","artist":"Khruangbin","album":"Mordechai","duration":287.041,"elapsedTime":1.9,\
            "timestamp":1790440710.978667,"playbackRate":0,"artworkIdentifier":"909f11df01084052","artworkData":"AAEC"},\
            {"id":"com.apple.WebKit.GPU:9565","bundleIdentifier":"com.apple.WebKit.GPU",\
            "parentBundleIdentifier":"com.apple.Safari","processIdentifier":9565,"displayName":null,"isPlaying":true,\
            "title":null,"artist":null,"album":null,"duration":null,"elapsedTime":null,"timestamp":null,\
            "playbackRate":null,"artworkIdentifier":null}]}
            """
        let message = try JSONDecoder().decode(NowPlayingPlayersMessage.self, from: Data(line.utf8))
        XCTAssertEqual(message.elected, 13335)
        XCTAssertEqual(message.players.count, 2)

        let music = message.players[0].snapshot
        XCTAssertEqual(music.title, "First Class")
        XCTAssertEqual(music.duration, 287.041)
        XCTAssertEqual(music.timestamp, Date(timeIntervalSince1970: 1790440710.978667))
        XCTAssertEqual(message.players[0].artworkData, "AAEC")

        let safari = message.players[1].snapshot
        XCTAssertEqual(safari.appBundleIdentifier, "com.apple.Safari")
        XCTAssertTrue(safari.isPlaying)
        XCTAssertEqual(safari.title, "")
        XCTAssertNil(safari.timestamp)
    }

    // MARK: - Routes

    func testEachAppIsReachedItsOwnWay() {
        XCTAssertEqual(MediaPlayerRoute(player: music), .music)
        XCTAssertEqual(MediaPlayerRoute(player: vlc), .vlc)
        XCTAssertEqual(MediaPlayerRoute(player: brave), .browser)
        XCTAssertEqual(MediaPlayerRoute(player: safari), .browser)
        XCTAssertEqual(
            MediaPlayerRoute(player: player(MediaAppBundleID.spotify, pid: 7, title: "Song")),
            .spotify
        )
        XCTAssertNil(MediaPlayerRoute(player: player("com.apple.podcasts", pid: 8, title: "Episode 12")))
        XCTAssertNil(MediaPlayerRoute(player: player("com.brave.Browser", pid: 9, title: " ")), "A tab is found by its title")
    }

    func testBrowsersCanPlayAndPauseButNotSkip() {
        XCTAssertTrue(MediaPlayerRoute.browser.supports(.togglePlay))
        XCTAssertFalse(MediaPlayerRoute.browser.supports(.next))
        XCTAssertFalse(MediaPlayerRoute.browser.supports(.previous))
        XCTAssertTrue(MediaPlayerRoute.music.supports(.next))
        XCTAssertTrue(MediaPlayerRoute.vlc.supports(.previous))
    }

    func testMusicAndSpotifyScripts() {
        XCTAssertEqual(MediaPlayerRoute.music.appleScript(.togglePlay), "tell application id \"com.apple.Music\" to playpause")
        XCTAssertEqual(MediaPlayerRoute.spotify.appleScript(.next), "tell application id \"com.spotify.client\" to next track")
        XCTAssertNil(MediaPlayerRoute.vlc.appleScript(.togglePlay))
    }

    func testVLCSkipsWithItsOwnEvents() {
        let code = VLCRemote.fourCharCode
        XCTAssertEqual(VLCRemote.event(.next).eventID, code("VLC4"))
        XCTAssertEqual(VLCRemote.event(.previous).eventID, code("VLC3"))
        XCTAssertEqual(VLCRemote.event(.togglePlay).eventClass, code("VLC#"))
    }

    func testBrowserPagesArePlayedThroughTheirOwnPlayerFirst() throws {
        let javaScript = PlaybackHandoffScripts.playMediaJavaScript
        XCTAssertFalse(PlaybackHandoffScripts.quoted(javaScript).contains("\n"), "Browsers get it as one line")
        XCTAssertFalse(javaScript.contains("//"), "On one line, a comment would swallow the rest")
        let click = try XCTUnwrap(javaScript.range(of: "control.click()"))
        let space = try XCTUnwrap(javaScript.range(of: "code: 'Space'"))
        let direct = try XCTUnwrap(javaScript.range(of: "media.play()"))
        XCTAssertLessThan(click.lowerBound, space.lowerBound)
        XCTAssertLessThan(space.lowerBound, direct.lowerBound)

        let script = try XCTUnwrap(PlaybackHandoffScripts.play(.init(bundleIdentifier: "com.apple.WebKit.GPU", title: safari.title)))
        XCTAssertTrue(script.contains("tell application id \"com.apple.Safari\""))
        XCTAssertTrue(script.contains("do JavaScript"))
        XCTAssertNil(PlaybackHandoffScripts.play(.init(bundleIdentifier: MediaAppBundleID.vlc, title: "A film.mkv")))
    }
}
