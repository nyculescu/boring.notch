//
//  PlaybackHandoffPolicyTests.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//
//  What gets paused when playback moves between apps, fed with Now Playing
//  updates in the order the adapter reports them: switching apps shows up
//  as an empty item, then the new app paused, then playing.
//

import Foundation
import XCTest
@testable import boringNotch

final class PlaybackHandoffPolicyTests: XCTestCase {
    private typealias Policy = PlaybackHandoffPolicy

    private let music = MediaAppBundleID.appleMusic
    private let brave = "com.brave.Browser"
    private let safari = "com.apple.Safari"
    private let podcasts = "com.apple.podcasts"
    private let video = "Un Grafician Fără Studii Muzicale | Hit-uri Virale"
    private let film = "Toy Story 5 | Disney+"
    private let pauseOnly = Policy.Settings(pausesOtherPlayers: true, resumesAppleMusic: false)
    private let pauseAndResume = Policy.Settings(pausesOtherPlayers: true, resumesAppleMusic: true)
    private let off = Policy.Settings(pausesOtherPlayers: false, resumesAppleMusic: true)

    private func update(
        _ policy: inout Policy,
        _ bundleIdentifier: String,
        _ title: String = "",
        playing: Bool,
        _ settings: Policy.Settings
    ) -> [Policy.Action] {
        policy.nowPlayingChanged(bundleIdentifier: bundleIdentifier, title: title, isPlaying: playing, settings: settings)
    }

    /// `app` takes Now Playing and starts playing, the way the adapter reports it.
    private func starts(
        _ policy: inout Policy,
        _ app: String,
        _ title: String,
        _ settings: Policy.Settings
    ) -> [Policy.Action] {
        update(&policy, "", playing: false, settings)
            + update(&policy, app, title, playing: false, settings)
            + update(&policy, app, title, playing: true, settings)
    }

    /// Completes a pending Apple Music pause the way it goes when Music isn't playing.
    private func settle(_ policy: inout Policy, _ settings: Policy.Settings) {
        if policy.isPausing { _ = policy.pauseFinished(pausedTrackID: nil, settings: settings) }
    }

    /// Apple Music is playing, then a Brave tab starts and takes Now Playing.
    private func braveStartsOverMusic(_ policy: inout Policy, _ settings: Policy.Settings) -> [Policy.Action] {
        update(&policy, music, "Stick Season", playing: true, settings) + starts(&policy, brave, video, settings)
    }

    /// Brave took over and the pause went through on track "A1".
    private func musicPausedForBrave(_ settings: Policy.Settings) -> Policy {
        var policy = Policy()
        _ = braveStartsOverMusic(&policy, settings)
        _ = policy.pauseFinished(pausedTrackID: "A1", settings: settings)
        return policy
    }

    // MARK: Pausing whatever was playing

    func testPausesAppleMusicWhenAnotherAppStartsPlaying() {
        var policy = Policy()
        XCTAssertEqual(braveStartsOverMusic(&policy, pauseOnly), [.pauseAppleMusic])
        XCTAssertEqual(policy.otherPlayer, brave)
    }

    func testPausesTheBrowserWhenAppleMusicStarts() {
        var policy = Policy()
        _ = starts(&policy, brave, video, pauseOnly)
        XCTAssertEqual(
            starts(&policy, music, "Stick Season", pauseOnly),
            [.pausePlayer(.init(bundleIdentifier: brave, title: video))]
        )
    }

    func testPausesOneBrowserWhenAnotherStarts() {
        var policy = Policy()
        _ = starts(&policy, brave, video, pauseOnly)
        settle(&policy, pauseOnly)
        // Apple Music is checked again at every start too.
        XCTAssertEqual(
            starts(&policy, safari, film, pauseOnly),
            [.pausePlayer(.init(bundleIdentifier: brave, title: video)), .pauseAppleMusic]
        )
        settle(&policy, pauseOnly)
        // And back: Safari was playing when Brave took over again.
        XCTAssertEqual(
            starts(&policy, brave, video, pauseOnly),
            [.pausePlayer(.init(bundleIdentifier: safari, title: film)), .pauseAppleMusic]
        )
    }

    func testTheInterruptedTitleIsTheLastOneItShowed() {
        var policy = Policy()
        _ = starts(&policy, brave, "First video", pauseOnly)
        XCTAssertEqual(update(&policy, brave, "Next video", playing: true, pauseOnly), [], "Same app, next video")
        XCTAssertEqual(
            starts(&policy, music, "Stick Season", pauseOnly),
            [.pausePlayer(.init(bundleIdentifier: brave, title: "Next video"))]
        )
    }

    func testLeavesAnAppThatWasAlreadyPausedAlone() {
        var policy = Policy()
        _ = starts(&policy, brave, video, pauseOnly)
        _ = update(&policy, brave, video, playing: false, pauseOnly)
        XCTAssertEqual(starts(&policy, music, "Stick Season", pauseOnly), [])
    }

    func testRemembersTheInterruptedAppUntilTheNextOneReallyStarts() {
        var policy = Policy()
        _ = starts(&policy, brave, video, pauseOnly)
        settle(&policy, pauseOnly)
        // Safari's page loads and shows up paused first; nothing to do yet.
        XCTAssertEqual(update(&policy, "", playing: false, pauseOnly), [])
        XCTAssertEqual(update(&policy, safari, film, playing: false, pauseOnly), [])
        XCTAssertEqual(
            update(&policy, safari, film, playing: true, pauseOnly),
            [.pausePlayer(.init(bundleIdentifier: brave, title: video)), .pauseAppleMusic]
        )
    }

    func testAnAppComingBackIsNotPausedByItself() {
        var policy = Policy()
        _ = starts(&policy, brave, video, pauseOnly)
        settle(&policy, pauseOnly)
        XCTAssertEqual(starts(&policy, brave, video, pauseOnly), [.pauseAppleMusic], "Only Apple Music is checked again")
        XCTAssertNil(policy.displacedPlayer)
    }

    func testLeavesEverythingAloneWhenPausingIsOff() {
        var policy = Policy()
        XCTAssertEqual(braveStartsOverMusic(&policy, off), [])
        XCTAssertEqual(starts(&policy, music, "Stick Season", off), [])
    }

    func testAppleMusicItselfAndEmptyItemsNeverTriggerAPause() {
        var policy = Policy()
        XCTAssertEqual(update(&policy, music, "Stick Season", playing: true, pauseOnly), [])
        XCTAssertEqual(update(&policy, "", playing: true, pauseOnly), [])
        XCTAssertNil(policy.otherPlayer)
        XCTAssertNil(policy.displacedPlayer)
    }

    func testPausesAppleMusicOnceWhileOtherAppsKeepPlaying() {
        var policy = musicPausedForBrave(pauseOnly)
        XCTAssertEqual(update(&policy, brave, video, playing: true, pauseOnly), [])
        XCTAssertEqual(update(&policy, brave, video, playing: false, pauseOnly), [])
        XCTAssertEqual(update(&policy, brave, video, playing: true, pauseOnly), [])
        XCTAssertEqual(
            starts(&policy, podcasts, "Episode 12", pauseOnly),
            [.pausePlayer(.init(bundleIdentifier: brave, title: video))],
            "Brave was playing; Apple Music is still paused from before"
        )
    }

    func testTriesAgainNextTimeWhenAppleMusicWasNotPlaying() {
        var policy = Policy()
        _ = braveStartsOverMusic(&policy, pauseAndResume)
        XCTAssertEqual(policy.pauseFinished(pausedTrackID: nil, settings: pauseAndResume), [])
        XCTAssertEqual(update(&policy, brave, video, playing: false, pauseAndResume), [], "Nothing to resume")
        XCTAssertEqual(update(&policy, brave, video, playing: true, pauseAndResume), [.pauseAppleMusic])
    }

    // MARK: Resuming Apple Music

    func testResumesThePausedTrackAfterTheOtherAppStops() {
        var policy = musicPausedForBrave(pauseAndResume)
        XCTAssertEqual(update(&policy, brave, video, playing: false, pauseAndResume), [.startResumeTimer])
        XCTAssertEqual(policy.resumeTimerFired(settings: pauseAndResume), [.resumeAppleMusic(trackID: "A1")])
        XCTAssertNil(policy.pausedTrackID)
    }

    func testClosingTheTabAlsoResumes() {
        var policy = musicPausedForBrave(pauseAndResume)
        XCTAssertEqual(update(&policy, "", playing: false, pauseAndResume), [.startResumeTimer])
        // Now Playing falls back to the paused Apple Music.
        XCTAssertEqual(update(&policy, music, "Stick Season", playing: false, pauseAndResume), [])
        XCTAssertEqual(policy.resumeTimerFired(settings: pauseAndResume), [.resumeAppleMusic(trackID: "A1")])
    }

    func testResumedMusicDoesNotPauseTheAppThatHadStopped() {
        var policy = musicPausedForBrave(pauseAndResume)
        _ = update(&policy, brave, video, playing: false, pauseAndResume)
        _ = policy.resumeTimerFired(settings: pauseAndResume)
        XCTAssertEqual(starts(&policy, music, "Stick Season", pauseAndResume), [])
    }

    func testDoesNotResumeWhenResumeIsOff() {
        var policy = musicPausedForBrave(pauseOnly)
        XCTAssertEqual(update(&policy, brave, video, playing: false, pauseOnly), [])
        XCTAssertEqual(policy.resumeTimerFired(settings: pauseOnly), [])
    }

    func testResumeTurnedOffWhileWaitingIsHonored() {
        var policy = musicPausedForBrave(pauseAndResume)
        _ = update(&policy, brave, video, playing: false, pauseAndResume)
        XCTAssertEqual(policy.resumeTimerFired(settings: pauseOnly), [])
    }

    func testOtherAppPlayingAgainCancelsTheResume() {
        var policy = musicPausedForBrave(pauseAndResume)
        XCTAssertEqual(update(&policy, brave, video, playing: false, pauseAndResume), [.startResumeTimer])
        XCTAssertEqual(update(&policy, brave, video, playing: true, pauseAndResume), [.cancelResumeTimer])
        // A timer that fires anyway (already on its way) resumes nothing.
        XCTAssertEqual(policy.resumeTimerFired(settings: pauseAndResume), [])
        XCTAssertEqual(policy.pausedTrackID, "A1")
    }

    func testPlayingAppleMusicByHandForgetsThePauseAndPausesTheVideo() {
        var policy = musicPausedForBrave(pauseAndResume)
        // Brave giving up the slot looks like it stopping, so the resume
        // timer starts, then Apple Music playing cancels it.
        XCTAssertEqual(
            starts(&policy, music, "Stick Season", pauseAndResume),
            [.startResumeTimer, .pausePlayer(.init(bundleIdentifier: brave, title: video)), .cancelResumeTimer]
        )
        XCTAssertNil(policy.pausedTrackID)
        XCTAssertEqual(update(&policy, music, "Stick Season", playing: false, pauseAndResume), [])
        XCTAssertEqual(policy.resumeTimerFired(settings: pauseAndResume), [])
    }

    func testPlayingAppleMusicByHandCancelsAWaitingResume() {
        var policy = musicPausedForBrave(pauseAndResume)
        _ = update(&policy, brave, video, playing: false, pauseAndResume)
        XCTAssertEqual(update(&policy, music, "Stick Season", playing: true, pauseAndResume), [.cancelResumeTimer])
        XCTAssertEqual(policy.resumeTimerFired(settings: pauseAndResume), [])
    }

    func testOtherAppStoppingWhileThePauseIsOnItsWayStillResumes() {
        var policy = Policy()
        XCTAssertEqual(braveStartsOverMusic(&policy, pauseAndResume), [.pauseAppleMusic])
        XCTAssertEqual(update(&policy, brave, video, playing: false, pauseAndResume), [])
        XCTAssertEqual(policy.pauseFinished(pausedTrackID: "A1", settings: pauseAndResume), [.startResumeTimer])
    }

    func testResetForgetsEverythingWithoutResuming() {
        var policy = musicPausedForBrave(pauseAndResume)
        _ = update(&policy, brave, video, playing: false, pauseAndResume)
        XCTAssertEqual(policy.reset(), [.cancelResumeTimer])
        XCTAssertEqual(policy, Policy())
        XCTAssertEqual(policy.resumeTimerFired(settings: pauseAndResume), [])
    }

    func testPauseFinishingAfterAResetIsIgnored() {
        var policy = Policy()
        _ = braveStartsOverMusic(&policy, pauseAndResume)
        _ = policy.reset()
        XCTAssertEqual(policy.pauseFinished(pausedTrackID: "A1", settings: pauseAndResume), [])
        XCTAssertNil(policy.pausedTrackID)
    }

    // MARK: Scripts

    func testPauseScriptResultCarriesTheTrackID() {
        func result(_ paused: Bool, _ trackID: String) -> NSAppleEventDescriptor {
            let list = NSAppleEventDescriptor.list()
            list.insert(NSAppleEventDescriptor(boolean: paused), at: 0)
            list.insert(NSAppleEventDescriptor(string: trackID), at: 0)
            return list
        }
        XCTAssertEqual(PlaybackHandoffScripts.pausedTrackID(from: result(true, "5F3A9C1D2E4B6A70")), "5F3A9C1D2E4B6A70")
        XCTAssertEqual(PlaybackHandoffScripts.pausedTrackID(from: result(true, "")), "")
        XCTAssertNil(PlaybackHandoffScripts.pausedTrackID(from: result(false, "")))
        XCTAssertNil(PlaybackHandoffScripts.pausedTrackID(from: nil))
    }

    func testResumeScriptOnlyEmbedsHexTrackIDs() {
        XCTAssertEqual(PlaybackHandoffScripts.sanitizedTrackID("0A1b\"; quit"), "0A1b")
        let script = PlaybackHandoffScripts.resumeAppleMusic(trackID: "5F3A\" & quit & \"")
        XCTAssertTrue(script.contains("if currentTrackID is \"5F3A\" then"))
    }

    func testTitlesAreQuotedForAppleScript() {
        XCTAssertEqual(PlaybackHandoffScripts.quoted("Say \"hi\" \\ bye\nnow"), "\"Say \\\"hi\\\" \\\\ bye now\"")
    }

    func testBrowsersArePausedInTheTabShowingTheTitle() throws {
        let braveScript = try XCTUnwrap(PlaybackHandoffScripts.pause(.init(bundleIdentifier: brave, title: " \(video) ")))
        XCTAssertTrue(braveScript.contains("tell application id \"com.brave.Browser\""))
        XCTAssertTrue(braveScript.contains("title of every tab of browserWindow"))
        XCTAssertTrue(braveScript.contains("contains \"\(video)\" then"))
        XCTAssertTrue(braveScript.contains("execute tab tabIndex of browserWindow javascript"))

        // Safari's media shows up under WebKit's GPU process.
        let safariScript = try XCTUnwrap(PlaybackHandoffScripts.pause(.init(bundleIdentifier: "com.apple.WebKit.GPU", title: film)))
        XCTAssertTrue(safariScript.contains("tell application id \"com.apple.Safari\""))
        XCTAssertTrue(safariScript.contains("name of every tab of browserWindow"))
        XCTAssertTrue(safariScript.contains("do JavaScript"))
    }

    func testPagesArePausedThroughTheirOwnPlayerFirst() throws {
        let javaScript = PlaybackHandoffScripts.pauseMediaJavaScript
        XCTAssertFalse(PlaybackHandoffScripts.quoted(javaScript).contains("\n"), "Browsers get it as one line")
        XCTAssertFalse(javaScript.contains("//"), "On one line, a comment would swallow the rest")
        let click = try XCTUnwrap(javaScript.range(of: "control.click()"))
        let space = try XCTUnwrap(javaScript.range(of: "code: 'Space'"))
        let direct = try XCTUnwrap(javaScript.range(of: "setTimeout"))
        XCTAssertLessThan(click.lowerBound, space.lowerBound)
        XCTAssertLessThan(space.lowerBound, direct.lowerBound)
    }

    func testNothingIsPausedWithoutATitleOrAWayToScriptTheApp() {
        XCTAssertNil(PlaybackHandoffScripts.pause(.init(bundleIdentifier: brave, title: "  ")), "Would match every tab")
        XCTAssertNil(PlaybackHandoffScripts.pause(.init(bundleIdentifier: podcasts, title: "Episode 12")))
        XCTAssertNotNil(PlaybackHandoffScripts.pause(.init(bundleIdentifier: MediaAppBundleID.spotify, title: "")))
    }

    func testVLCIsPausedWithAppleEventsNotAppleScript() {
        // Compiling AppleScript against VLC's old-style dictionary crashed the sandboxed app.
        XCTAssertNil(PlaybackHandoffScripts.pause(.init(bundleIdentifier: MediaAppBundleID.vlc, title: "")))

        let code = VLCRemote.fourCharCode
        let isPlaying = VLCRemote.isPlayingEvent()
        XCTAssertEqual(isPlaying.eventClass, code("core"))
        XCTAssertEqual(isPlaying.eventID, code("getd"))
        let property = isPlaying.paramDescriptor(forKeyword: code("----"))
        XCTAssertEqual(property?.descriptorType, code("obj "))
        XCTAssertEqual(property?.forKeyword(code("seld"))?.typeCodeValue, code("AAPL"), "VLC's `playing`")
        XCTAssertEqual(property?.forKeyword(code("want"))?.typeCodeValue, code("prop"))

        let toggle = VLCRemote.toggleEvent()
        XCTAssertEqual(toggle.eventClass, code("VLC#"))
        XCTAssertEqual(toggle.eventID, code("VLC1"), "VLC's `play`, which toggles")
        XCTAssertEqual(toggle.attributeDescriptor(forKeyword: code("addr"))?.descriptorType, code("bund"), "Aimed at VLC by bundle ID")
    }

    func testPauseOutcomeReadsTheCountAndTheError() {
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(int32: 0), at: 0)
        list.insert(NSAppleEventDescriptor(string: "Executing JavaScript through AppleScript is turned off."), at: 0)
        let outcome = PlaybackHandoffScripts.pauseOutcome(from: list)
        XCTAssertEqual(outcome.paused, 0)
        XCTAssertEqual(outcome.failure, "Executing JavaScript through AppleScript is turned off.")
        XCTAssertEqual(PlaybackHandoffScripts.pauseOutcome(from: nil).paused, 0)
    }
}
