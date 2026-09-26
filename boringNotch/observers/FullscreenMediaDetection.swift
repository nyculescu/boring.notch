//
//  FullscreenMediaDetection.swift
//  boringNotch
//
//  Created by Richard Kunkli on 06/09/2024.
//

import AppKit
import Combine
import Defaults
import MacroVisionKit

@MainActor
final class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()

    @Published var fullscreenStatus: [String: Bool] = [:]

    private var monitorTask: Task<Void, Never>?
    /// Screens showing a full-screen Space, from MacroVisionKit.
    private var spaceStatus: [String: Bool] = [:]
    /// Screens the media app covers with a window instead of a Space.
    private var windowedScreens: Set<String> = []
    private var windowCheck: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        startMonitoring()
        watchWindowedFullscreen()
    }

    deinit {
        monitorTask?.cancel()
    }

    private func startMonitoring() {
        monitorTask = Task { @MainActor in
            let stream = await FullScreenMonitor.shared.spaceChanges()
            for await spaces in stream {
                updateStatus(with: spaces)
            }
        }
    }

    private func updateStatus(with spaces: [MacroVisionKit.FullScreenMonitor.SpaceInfo]) {
        var newStatus: [String: Bool] = [:]

        for space in spaces {
            if let uuid = space.screenUUID {
                let shouldDetect: Bool
                if Defaults[.hideNotchOption] == .nowPlayingOnly, let musicSourceBundle = MusicManager.shared.bundleIdentifier {
                    shouldDetect = space.runningApps.contains(musicSourceBundle)
                } else {
                    shouldDetect = true
                }
                newStatus[uuid] = shouldDetect
            }
        }

        spaceStatus = newStatus
        publishStatus()
    }

    private func publishStatus() {
        var status = spaceStatus
        for uuid in windowedScreens {
            status[uuid] = true
        }
        if status != fullscreenStatus {
            fullscreenStatus = status
        }
    }

    // MARK: - Full screen without a Space

    /// Players like VLC go full screen with a window that covers the screen,
    /// which MacroVisionKit, watching Spaces, never sees, and nothing posts a
    /// notification for it. So while the media app is the app in front, its
    /// windows are checked once a second. Only the media app is watched, as
    /// "Hide for media app only" asks; "Hide for all apps" gets the same.
    private func watchWindowedFullscreen() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .map { _ in () }
            .merge(with: MusicManager.shared.$bundleIdentifier.removeDuplicates().map { _ in () })
            .sink { [weak self] in self?.updateWindowCheck() }
            .store(in: &cancellables)
    }

    private func updateWindowCheck() {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard frontmost != nil, frontmost == MusicManager.shared.bundleIdentifier else {
            windowCheck?.invalidate()
            windowCheck = nil
            setWindowedScreens([])
            return
        }
        if windowCheck == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkWindowedFullscreen() }
            }
            timer.tolerance = 0.5
            windowCheck = timer
        }
        checkWindowedFullscreen()
    }

    private func checkWindowedFullscreen() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        let displays = NSScreen.screens.compactMap { screen -> FullscreenWindows.Display? in
            guard let uuid = screen.displayUUID, let displayID = screen.cgDisplayID else { return nil }
            return FullscreenWindows.Display(uuid: uuid, bounds: CGDisplayBounds(displayID))
        }
        setWindowedScreens(FullscreenWindows.displays(
            coveredBy: frontmost.processIdentifier,
            windows: FullscreenWindows.onScreen(),
            displays: displays
        ))
    }

    private func setWindowedScreens(_ screens: Set<String>) {
        guard screens != windowedScreens else { return }
        windowedScreens = screens
        publishStatus()
    }
}
