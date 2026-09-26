//
//  MediaPlayerLineup.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  Which players get a page after the live one, in what order, and where a
//  swipe lands. Kept apart from the views and the helper so it can be tested.
//

import Foundation

/// The Media tab's first page is always the live player (MusicManager, which
/// follows the app macOS elected). Every other player with something to
/// show gets a page after it, the one played most recently first, then in
/// the order they turned up. A player is the live page's when it's the app
/// the live page shows with the same title, or that app's elected process
/// (its title can move on a moment before the live page's). When the live
/// page lags behind a switch of apps, the newly elected app gets a page
/// until the live page catches up, rather than disappearing from both.
struct MediaPlayerLineup: Equatable {
    /// What the live page is showing, so the same player isn't shown twice.
    struct LivePage: Equatable {
        var bundleIdentifier: String?
        var title: String
    }

    /// The pages after the live one, in order.
    private(set) var players: [MediaPlayerSnapshot] = []

    private var firstSeen: [String: Int] = [:]
    private var lastStarted: [String: Int] = [:]
    private var playing: Set<String> = []
    private var clock = 0

    mutating func update(with all: [MediaPlayerSnapshot], elected: Int32?, live: LivePage) {
        let present = Set(all.map(\.id))
        firstSeen = firstSeen.filter { present.contains($0.key) }
        lastStarted = lastStarted.filter { present.contains($0.key) }
        playing.formIntersection(present)

        for player in all {
            if firstSeen[player.id] == nil {
                clock += 1
                firstSeen[player.id] = clock
            }
            if player.isPlaying, !playing.contains(player.id) {
                clock += 1
                lastStarted[player.id] = clock
            }
            if player.isPlaying {
                playing.insert(player.id)
            } else {
                playing.remove(player.id)
            }
        }

        players = all
            .filter { player in
                let isLivePage = player.appBundleIdentifier == live.bundleIdentifier
                    && (player.title == live.title || player.processIdentifier == elected)
                return !isLivePage && !player.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { lhs, rhs in
                let lhsStarted = lastStarted[lhs.id] ?? 0
                let rhsStarted = lastStarted[rhs.id] ?? 0
                if lhsStarted != rhsStarted {
                    return lhsStarted > rhsStarted
                }
                return (firstSeen[lhs.id] ?? 0) < (firstSeen[rhs.id] ?? 0)
            }
    }
}

enum MediaPlayerPaging {
    struct Move: Equatable {
        /// The player whose page comes next; nil is the live page.
        let selection: String?
    }

    /// Where `step` goes from `selection` (nil is the live page) among the
    /// other players' pages `ids`: one page on, never past either end, so
    /// nil when there's no page that way.
    static func move(
        _ step: TwoFingerSwipeTracker.Step,
        from selection: String?,
        among ids: [String]
    ) -> Move? {
        let pages: [String?] = [nil] + ids
        let target = index(of: selection, among: ids) + (step == .forward ? 1 : -1)
        guard pages.indices.contains(target) else { return nil }
        return Move(selection: pages[target])
    }

    /// The page `selection` is on, counting the live page as 0.
    static func index(of selection: String?, among ids: [String]) -> Int {
        selection.flatMap { id in ids.firstIndex(of: id).map { $0 + 1 } } ?? 0
    }
}
