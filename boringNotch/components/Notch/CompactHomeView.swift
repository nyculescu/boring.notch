//
//  CompactHomeView.swift
//  boringNotch
//
//  Compact mode's opened panel: a rail of tabs beside a smaller home, shelf
//  or clipboard. The home tab holds just the now-playing essentials — art,
//  title, scrubber, transport — with no calendar or mirror.
//
//  The player started from Atoll's MinimalisticMusicPlayerView
//  (https://github.com/Ebullioscopic/Atoll, GPL-3.0, itself a boring.notch
//  fork) — 12/10pt title and artist, a visualizer to their right, then a
//  transport row — and is packed tighter here to fit a shorter panel: the
//  scrubber sits beside the art under the title and artist, with its
//  timestamps either side of the bar rather than below it.
//
//  Transport and slider are deliberately shared with the standard layout
//  (MusicControlSlotButton / MusicSliderView) rather than ported separately,
//  so seeking and the buttons behave identically in both layouts instead of
//  drifting apart.
//

import Defaults
import SwiftUI

/// Compact mode's opened content: the tab rail beside the selected tab, in
/// one fixed frame so switching tabs never resizes the panel.
struct CompactNotchView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat
    @Binding var isHoveringMusicArea: Bool

    var body: some View {
        HStack(spacing: 8) {
            TabSelectionView(axis: .vertical)

            selectedTab
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: compactOpenContentSize.width, height: compactOpenContentSize.height)
    }

    @ViewBuilder
    private var selectedTab: some View {
        switch coordinator.currentView {
        case .home:
            CompactHomeView(
                albumArtNamespace: albumArtNamespace,
                horizontalMediaGestureFeedback: horizontalMediaGestureFeedback
            )
            .onHover { hovering in
                isHoveringMusicArea = hovering
            }
            .onDisappear {
                isHoveringMusicArea = false
            }
        case .shelf:
            ShelfView(
                dropInteraction: vm.dropInteraction,
                animation: vm.animation
            )
        case .clipboard:
            ClipboardView()
        }
    }
}

struct CompactHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat

    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast

    @Default(.coloredSpectrogram) private var coloredSpectrogram
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit
    @Default(.playerColorTinting) private var playerColorTinting
    @Default(.showBatteryIndicator) private var showBatteryIndicator
    @Default(.showRemainingTime) private var showRemainingTime

    /// Also the header's height: title, artist and scrubber all fit beside
    /// the art.
    private let albumArtWidth: CGFloat = 44
    private let headerSpacing: CGFloat = 8
    private let batteryWidth: CGFloat = 24
    private let vizBarWidth: CGFloat = 16

    /// The column right of the title and artist: battery over visualizer.
    /// BatteryView draws 1pt wider than its batteryWidth.
    private var statusWidth: CGFloat {
        showBatteryIndicator ? batteryWidth + 1 : vizBarWidth
    }

    // No idle branch, deliberately. The standard layout has none either —
    // it renders whatever MusicManager last cached, so a paused or stopped
    // track keeps its art, title and scrub position. A "Nothing Playing"
    // placeholder here made compact mode lose state the full layout keeps.
    var body: some View {
        VStack(spacing: 4) {
            header
                .frame(height: albumArtWidth)

            transport
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Header

    private var header: some View {
        GeometryReader { geo in
            let columnWidth = max(0, geo.size.width - albumArtWidth - headerSpacing)
            let textWidth = max(0, columnWidth - statusWidth - headerSpacing)

            HStack(alignment: .center, spacing: headerSpacing) {
                compactAlbumArt

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: headerSpacing) {
                        // No spacing: title, artist and scrubber already fill
                        // the art's height to within a point.
                        VStack(alignment: .leading, spacing: 0) {
                            MarqueeText(
                                musicManager.songTitle,
                                font: .system(size: 12, weight: .semibold),
                                color: .white,
                                frameWidth: textWidth
                            )

                            Text(musicManager.artistName)
                                .font(.system(size: 10))
                                .foregroundStyle(
                                    playerColorTinting
                                        ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
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
            // BoringHeader carries the battery in the standard layout;
            // compact mode has no header, so it rides along here.
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
                isPlaying: musicManager.isPlaying,
                tintColor: coloredSpectrogram
                    ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                    : .gray
            )
            .frame(width: vizBarWidth, height: 12)
        }
    }

    // MARK: - Progress

    private var progressRow: some View {
        MusicPlaybackTimeline(playbackRate: musicManager.playbackRate) { date in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying,
                onValueChange: { MusicManager.shared.seek(to: $0) },
                trailingLabel: showRemainingTime ? .remaining : .duration,
                timestampPlacement: .inline
            )
        }
        .onAppear { sliderValue = musicManager.elapsedTime }
    }

    // MARK: - Transport

    /// The user's configured control slots, clamped like the standard
    /// layout's activeSlots, rendered through the same MusicControlSlotButton
    /// — so sizing, glyphs and the swipe-to-skip bounce match exactly.
    private var displayedSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        return slotConfig
            .padded(to: sanitizedLimit, filler: .none)
            .prefix(sanitizedLimit)
            .map { $0 }
    }

    private var transport: some View {
        HStack(spacing: 6) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { _, slot in
                MusicControlSlotButton(
                    slot: slot,
                    horizontalMediaGestureFeedback: horizontalMediaGestureFeedback
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Opens the player, like the album art in the standard layout.
    private var compactAlbumArt: some View {
        Button {
            musicManager.openMusicApp()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: musicManager.albumArt)
                    .resizable().scaledToFill()
                    .frame(width: albumArtWidth, height: albumArtWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                // Badge scaled to this art. AlbumArtView's is a fixed 30pt with
                // a +10/+10 offset, sized for the 120pt art in the full layout —
                // on art this small it spills outside the corner.
                if !musicManager.usingAppIconForArtwork {
                    appIcon(for: musicManager.bundleIdentifier ?? MediaAppBundleID.appleMusic)
                        .resizable().scaledToFit()
                        .frame(width: 18, height: 18)
                        .offset(x: 5, y: 5)
                }
            }
            .frame(width: albumArtWidth, height: albumArtWidth)
        }
        .buttonStyle(PlainButtonStyle())
        .help(musicManager.openPlayerHint)
    }
}

/// Output device list shared by both layouts' media-output buttons.
/// Row treatment follows macOS's AirPlay output menu: rounded highlight on
/// hover, circular icon badge marking the active output, no checkmark.
struct AudioOutputPicker: View {
    @ObservedObject var routeManager: AudioRouteManager
    let onSelect: () -> Void

    /// Apple's rows use a softly rounded rectangle, not a full pill.
    private let rowCornerRadius: CGFloat = 8
    private let listInset: CGFloat = 8
    private let badgeSize: CGFloat = 24
    private let hoverFill: CGFloat = 0.1
    private let pressedFill: CGFloat = 0.18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Output")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            if routeManager.devices.isEmpty {
                // Enumeration is async, so an empty list on first open is
                // normal rather than an error worth alarming anyone about.
                Text("Looking for devices…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            } else {
                ForEach(routeManager.devices) { device in
                    deviceRow(device)
                }
                .padding(.horizontal, listInset)
                .padding(.bottom, 6)
            }
        }
        .frame(minWidth: 220)
    }

    private func deviceRow(_ device: AudioOutputDevice) -> some View {
        let isSelected = device.id == routeManager.activeDeviceID

        return Button {
            routeManager.select(device)
            onSelect()
        } label: {
            HStack(spacing: 10) {
                deviceIcon(device, isSelected: isSelected)

                Text(device.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 10)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: rowCornerRadius))
        }
        .buttonStyle(AudioOutputRowButtonStyle(
            cornerRadius: rowCornerRadius,
            hoverFill: hoverFill,
            pressedFill: pressedFill
        ))
    }

    /// White badge + accent glyph for the active output, dim badge + white
    /// glyph for the rest.
    @ViewBuilder
    private func deviceIcon(_ device: AudioOutputDevice, isSelected: Bool) -> some View {
        Image(systemName: device.iconName)
            .font(.system(size: badgeSize * 0.55, weight: .regular))
            .foregroundStyle(isSelected ? Color.accentColor : Color.white)
            .frame(width: badgeSize, height: badgeSize)
            .background(isSelected ? Color.white : Color.white.opacity(0.22), in: Circle())
    }
}

private struct AudioOutputRowButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    let hoverFill: CGFloat
    let pressedFill: CGFloat

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let fill: CGFloat
        if configuration.isPressed {
            fill = pressedFill
        } else {
            fill = isHovering ? hoverFill : 0
        }

        return configuration.label
            .background(Color.white.opacity(fill), in: RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
    }
}
