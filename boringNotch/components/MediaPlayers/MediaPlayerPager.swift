//
//  MediaPlayerPager.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  The Media tab's player area as pages: the live player first, then every
//  other app with something to show, one two-finger swipe apart, with dots
//  on the album art when there's more than one.
//

import AppKit
import Defaults
import SwiftUI

struct MediaPlayerPager<Live: View>: View {
    enum Layout {
        case standard
        case compact
    }

    @ObservedObject private var players = NowPlayingPlayersService.shared
    @ObservedObject private var musicManager = MusicManager.shared
    /// The player whose page shows; nil is the live page.
    @State private var selection: String?
    /// Its process, to tell when it has become the Now Playing app.
    @State private var selectedProcess: Int32?
    @State private var pageTransition: AnyTransition = .push(from: .trailing)
    @State private var bounceOffset: CGFloat = 0

    let layout: Layout
    @ViewBuilder let live: () -> Live

    private var others: [MediaPlayerSnapshot] {
        players.otherPlayers
    }

    private var selectedPlayer: MediaPlayerSnapshot? {
        selection.flatMap { id in others.first { $0.id == id } }
    }

    var body: some View {
        ZStack {
            if let player = selectedPlayer {
                page(for: player)
                    .id(player.id)
                    .transition(pageTransition)
            } else {
                live()
                    .transition(pageTransition)
            }
        }
        .offset(x: bounceOffset)
        .overlayPreferenceValue(MediaPlayerArtAnchorKey.self) { anchor in
            if let anchor, !others.isEmpty {
                GeometryReader { proxy in
                    pageDots(on: proxy[anchor])
                }
                .allowsHitTesting(false)
            }
        }
        .background(TwoFingerSwipeMonitor { step in move(step) })
        .onAppear {
            players.refresh()
        }
        // Another app starting takes the notch back to the live page. A
        // player started from its own page stays on screen until the live
        // page shows it (its page then leaves the lineup), and then hands
        // over without a slide, since it's the same player.
        .onChange(of: players.electedProcessIdentifier) { _, elected in
            guard selectedProcess != elected else { return }
            showLivePage(becameLive: false)
        }
        .onChange(of: others.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) {
                showLivePage(becameLive: selectedProcess == players.electedProcessIdentifier)
            }
        }
    }

    @ViewBuilder
    private func page(for player: MediaPlayerSnapshot) -> some View {
        switch layout {
        case .standard:
            MediaPlayerPreviewView(player: player)
        case .compact:
            CompactMediaPlayerPreviewView(player: player)
        }
    }

    // MARK: - Swiping

    /// One page on, with the page leaving on the side the swipe pushes it
    /// to. The edge is set first and the page changes on the next turn, as
    /// in StickyNotesView; at either end the page gives a small nudge instead.
    private func move(_ step: TwoFingerSwipeTracker.Step) {
        guard !others.isEmpty else { return }
        guard let move = MediaPlayerPaging.move(step, from: selection, among: others.map(\.id)) else {
            nudge(toward: step)
            return
        }
        pageTransition = .push(from: step == .forward ? .trailing : .leading)
        let process = move.selection.flatMap { id in others.first { $0.id == id }?.processIdentifier }
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.3)) {
                selection = move.selection
                selectedProcess = process
            }
        }
        if Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func showLivePage(becameLive: Bool) {
        guard selection != nil else { return }
        pageTransition = becameLive ? .opacity : .push(from: .leading)
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.3)) {
                selection = nil
                selectedProcess = nil
            }
        }
    }

    private func nudge(toward step: TwoFingerSwipeTracker.Step) {
        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.6)) {
            bounceOffset = step == .forward ? -10 : 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.7)) {
                bounceOffset = 0
            }
        }
    }

    // MARK: - Page dots

    private func pageDots(on art: CGRect) -> some View {
        let count = others.count + 1
        let current = MediaPlayerPaging.index(of: selectedPlayer?.id, among: others.map(\.id))
        let dotSize: CGFloat = layout == .standard ? 5 : 4
        let position: CGPoint
        switch layout {
        case .standard:
            // Along the art's bottom edge, which shrinks with the art when
            // the player is paused (AlbumArtView scales it to 0.85).
            let isPlaying = selectedPlayer?.isPlaying ?? musicManager.isPlaying
            let scale: CGFloat = isPlaying ? 1 : 0.85
            position = CGPoint(x: art.midX, y: art.midY + (art.maxY - 9 - art.midY) * scale)
        case .compact:
            // Along the top: the app's badge sits in the bottom corner.
            position = CGPoint(x: art.midX, y: art.minY + 6)
        }
        return HStack(spacing: dotSize - 1) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(index == current ? 0.95 : 0.4))
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .padding(.horizontal, dotSize)
        .padding(.vertical, dotSize - 2)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .position(position)
        .animation(.smooth(duration: 0.3), value: current)
    }
}

/// Where a player page's album art is, so the page dots can sit on it.
struct MediaPlayerArtAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Marks this view as a player page's album art (see MediaPlayerPager).
    func mediaPlayerArtAnchor() -> some View {
        anchorPreference(key: MediaPlayerArtAnchorKey.self, value: .bounds) { $0 }
    }
}
