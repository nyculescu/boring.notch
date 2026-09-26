//
//  MediaPlayerPreviewView.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  Another player's page in the Media tab, for both layouts. The pages copy
//  the live player's look (AlbumArtView and MusicControlsView, CompactHomeView)
//  so nothing jumps when swiping between them; keep them in step when the
//  live player changes. Only what the app can take from the notch works
//  (see MediaPlayerRemote); the rest of the controls are shown dimmed.
//

import AppKit
import Defaults
import SwiftUI

/// The picture, color and actions a player page shows.
@MainActor
private struct PlayerPageContent {
    let player: MediaPlayerSnapshot
    let artwork: MediaPlayerArtwork?

    var image: NSImage {
        artwork?.image ?? appIconAsNSImage(for: player.appBundleIdentifier) ?? defaultImage
    }

    var usesAppIcon: Bool {
        artwork == nil
    }

    var tint: NSColor {
        artwork?.averageColor ?? .white
    }

    var openHint: LocalizedStringKey {
        if let name = NowPlayingPlayersService.shared.appName(for: player.appBundleIdentifier) {
            return "Open \(name)"
        }
        return "Open the music player"
    }

    func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.appBundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

struct MediaPlayerPreviewView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var players = NowPlayingPlayersService.shared
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit
    @Default(.showRemainingTime) private var showRemainingTime
    let player: MediaPlayerSnapshot

    private var content: PlayerPageContent {
        PlayerPageContent(player: player, artwork: players.artwork[player.id])
    }

    var body: some View {
        HStack {
            albumArt
                .frame(width: 120)
                .padding(.all, 5 * (vm.notchSize.height / 190))
            controls
                .compositingGroup()
        }
        .contentShape(Rectangle())
    }

    // MARK: - Album art (as AlbumArtView)

    private var albumArt: some View {
        let content = content
        let cornerRadius = MusicPlayerImageSizes.cornerRadiusInset.opened
        return ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                Image(nsImage: content.image)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .scaleEffect(x: 1.3, y: 1.4)
                    .rotationEffect(.degrees(92))
                    .blur(radius: 40)
                    .opacity(player.isPlaying ? 0.5 : 0)
            }
            ZStack {
                Button {
                    content.openApp()
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(nsImage: content.image)
                            .interpolation(.high)
                            .resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                            .mediaPlayerArtAnchor()
                            .albumArtHoverGlow(content.image, cornerRadius: cornerRadius, radius: 8.8)
                        if !content.usesAppIcon {
                            appIcon(for: player.appBundleIdentifier)
                                .resizable().scaledToFit()
                                .frame(width: 30, height: 30)
                                .offset(x: 10, y: 10)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .help(content.openHint)
                .scaleEffect(player.isPlaying ? 1 : 0.85)

                Rectangle()
                    .foregroundColor(Color.black)
                    .opacity(player.isPlaying ? 0 : 0.8)
                    .blur(radius: 50)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Controls (as MusicControlsView)

    private var controls: some View {
        VStack(alignment: .leading) {
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 4) {
                    VStack(alignment: .leading, spacing: 0) {
                        MarqueeText(player.title, font: .headline, color: .white, frameWidth: geo.size.width)
                        MarqueeText(
                            player.artist,
                            font: .headline,
                            color: Defaults[.playerColorTinting]
                                ? Color(nsColor: content.tint).ensureMinimumBrightness(factor: 0.6) : .gray,
                            frameWidth: geo.size.width
                        )
                        .fontWeight(.medium)
                    }
                    progress
                }
            }
            .padding(.top, 10)
            .padding(.leading, 5)

            HStack(spacing: 6) {
                ForEach(Array(activeSlots.enumerated()), id: \.offset) { _, slot in
                    MediaPlayerPreviewSlot(slot: slot, player: player)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// The live player's slider, read-only: another player can't be seeked
    /// from here, and its timeline only runs while it plays.
    private var progress: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !player.isPlaying)) { context in
            MusicSliderView(
                sliderValue: .constant(player.position(at: context.date)),
                duration: .constant(player.duration),
                lastDragged: .constant(.distantPast),
                color: content.tint,
                dragging: .constant(false),
                currentDate: context.date,
                timestampDate: player.timestamp ?? .distantPast,
                elapsedTime: player.elapsedTime,
                playbackRate: player.playbackRate,
                isPlaying: player.isPlaying,
                onValueChange: { _ in },
                trailingLabel: showRemainingTime ? .remaining : .duration
            )
            .padding(.top, 5)
            .frame(height: 36)
            .allowsHitTesting(false)
        }
    }

    /// As MusicControlsView's activeSlots.
    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(max(slotLimit, MusicControlButton.minSlotCount), MusicControlButton.maxSlotCount)
        let result = Array(slotConfig.padded(to: sanitizedLimit, filler: .none).prefix(sanitizedLimit))
        let shouldHideEdges = Defaults[.showCalendar] && Defaults[.showMirror]
            && vm.camera.cameraAvailable && vm.camera.isSessionRunning
        if shouldHideEdges && result.count >= 5 {
            return Array(result.dropFirst().dropLast())
        }
        return result
    }
}

struct CompactMediaPlayerPreviewView: View {
    @ObservedObject private var players = NowPlayingPlayersService.shared
    @ObservedObject private var batteryModel = BatteryStatusViewModel.shared
    @Default(.coloredSpectrogram) private var coloredSpectrogram
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit
    @Default(.playerColorTinting) private var playerColorTinting
    @Default(.showBatteryIndicator) private var showBatteryIndicator
    @Default(.showRemainingTime) private var showRemainingTime
    let player: MediaPlayerSnapshot

    // As CompactHomeView.
    private let albumArtWidth: CGFloat = 44
    private let headerSpacing: CGFloat = 8
    private let batteryWidth: CGFloat = 24
    private let vizBarWidth: CGFloat = 16

    private var statusWidth: CGFloat {
        showBatteryIndicator ? batteryWidth + 1 : vizBarWidth
    }

    private var content: PlayerPageContent {
        PlayerPageContent(player: player, artwork: players.artwork[player.id])
    }

    var body: some View {
        VStack(spacing: 4) {
            header
                .frame(height: albumArtWidth)
            transport
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .buttonStyle(PlainButtonStyle())
    }

    private var header: some View {
        GeometryReader { geo in
            let columnWidth = max(0, geo.size.width - albumArtWidth - headerSpacing)
            let textWidth = max(0, columnWidth - statusWidth - headerSpacing)

            HStack(alignment: .center, spacing: headerSpacing) {
                albumArt

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: headerSpacing) {
                        VStack(alignment: .leading, spacing: 0) {
                            MarqueeText(
                                player.title,
                                font: .system(size: 12, weight: .semibold),
                                color: .white,
                                frameWidth: textWidth
                            )
                            Text(player.artist)
                                .font(.system(size: 10))
                                .foregroundStyle(
                                    playerColorTinting
                                        ? Color(nsColor: content.tint).ensureMinimumBrightness(factor: 0.6)
                                        : .gray
                                )
                                .lineLimit(1)
                        }
                        .frame(width: textWidth, alignment: .leading)

                        status
                            .frame(width: statusWidth)
                    }

                    Spacer(minLength: 0)

                    progressRow
                }
                .frame(width: columnWidth, height: albumArtWidth)
            }
        }
    }

    private var status: some View {
        VStack(spacing: 4) {
            if showBatteryIndicator {
                BoringBatteryView(
                    batteryWidth: batteryWidth,
                    isCharging: batteryModel.isCharging,
                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                    isPluggedIn: batteryModel.isPluggedIn,
                    levelBattery: batteryModel.levelBattery,
                    maxCapacity: batteryModel.maxCapacity,
                    timeToFullCharge: batteryModel.timeToFullCharge,
                    timeToDischarge: batteryModel.timeToDischarge,
                    maxAdapterWatts: batteryModel.maxAdapterWatts,
                    isForNotification: false,
                    showsPercentage: false
                )
            }

            MusicVisualizer(
                isPlaying: player.isPlaying,
                tintColor: coloredSpectrogram
                    ? Color(nsColor: content.tint).ensureMinimumBrightness(factor: 0.6)
                    : .gray
            )
            .frame(width: vizBarWidth, height: 12)
        }
    }

    private var progressRow: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !player.isPlaying)) { context in
            MusicSliderView(
                sliderValue: .constant(player.position(at: context.date)),
                duration: .constant(player.duration),
                lastDragged: .constant(.distantPast),
                color: content.tint,
                dragging: .constant(false),
                currentDate: context.date,
                timestampDate: player.timestamp ?? .distantPast,
                elapsedTime: player.elapsedTime,
                playbackRate: player.playbackRate,
                isPlaying: player.isPlaying,
                onValueChange: { _ in },
                trailingLabel: showRemainingTime ? .remaining : .duration,
                timestampPlacement: .inline
            )
            .allowsHitTesting(false)
        }
    }

    private var transport: some View {
        let sanitizedLimit = min(max(slotLimit, MusicControlButton.minSlotCount), MusicControlButton.maxSlotCount)
        let slots = Array(slotConfig.padded(to: sanitizedLimit, filler: .none).prefix(sanitizedLimit))
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                MediaPlayerPreviewSlot(slot: slot, player: player)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var albumArt: some View {
        let content = content
        return Button {
            content.openApp()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: content.image)
                    .resizable().scaledToFill()
                    .frame(width: albumArtWidth, height: albumArtWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .mediaPlayerArtAnchor()
                    .albumArtHoverGlow(content.image, cornerRadius: 10, radius: 5.5)

                if !content.usesAppIcon {
                    appIcon(for: player.appBundleIdentifier)
                        .resizable().scaledToFit()
                        .frame(width: 18, height: 18)
                        .offset(x: 5, y: 5)
                }
            }
            .frame(width: albumArtWidth, height: albumArtWidth)
        }
        .buttonStyle(PlainButtonStyle())
        .help(content.openHint)
    }
}

/// A control on another player's page: the live player's button, doing
/// what that app can take from the notch, dimmed where it can't.
struct MediaPlayerPreviewSlot: View {
    let slot: MusicControlButton
    let player: MediaPlayerSnapshot

    var body: some View {
        Group {
            switch slot {
            case .playPause:
                button(.togglePlay, icon: player.isPlaying ? "pause.fill" : "play.fill", scale: .large)
            case .previous:
                button(.previous, icon: "backward.fill", scale: .medium)
            case .next:
                button(.next, icon: "forward.fill", scale: .medium)
            case .mediaOutput:
                // The Mac's output, the same whichever player is showing.
                MediaOutputSlotButton()
            case .none:
                Color.clear.frame(height: 1)
            default:
                // Shuffle, repeat, volume, favorites and seeking are for the
                // app that's playing.
                unavailable(icon: liveIcon)
            }
        }
        .help(helpText)
        .accessibilityLabel(helpText)
        .accessibilityHidden(slot == .none)
    }

    private var command: MediaPlayerCommand? {
        switch slot {
        case .playPause: .togglePlay
        case .previous: .previous
        case .next: .next
        default: nil
        }
    }

    private var isAvailable: Bool {
        command.map { MediaPlayerRemote.supports($0, for: player) } ?? (slot == .mediaOutput || slot == .none)
    }

    @ViewBuilder
    private func button(_ command: MediaPlayerCommand, icon: String, scale: Image.Scale) -> some View {
        if MediaPlayerRemote.supports(command, for: player) {
            HoverButton(icon: icon, scale: scale) {
                MediaPlayerRemote.perform(command, on: player)
            }
        } else {
            unavailable(icon: icon, scale: scale)
        }
    }

    private func unavailable(icon: String, scale: Image.Scale = .medium) -> some View {
        HoverButton(icon: icon, scale: scale) {}
            .opacity(0.3)
            .allowsHitTesting(false)
    }

    /// The glyph the live player shows in this slot.
    private var liveIcon: String {
        switch slot {
        case .shuffle: "shuffle"
        case .repeatMode: "repeat"
        case .volume: "speaker.wave.2.fill"
        case .favorite: "heart"
        case .goBackward: "gobackward.15"
        case .goForward: "goforward.15"
        default: "questionmark"
        }
    }

    private var helpText: String {
        if isAvailable {
            return slot.actionLabel(isPlaying: player.isPlaying, isFavorite: false)
        }
        if slot == .playPause {
            return String(localized: "Boring Notch can't control this app")
        }
        return String(localized: "Play it to use \(slot.label)")
    }
}
