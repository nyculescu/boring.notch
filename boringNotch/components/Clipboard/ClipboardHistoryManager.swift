//
//  ClipboardHistoryManager.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import AppKit
import Combine
import Defaults

/// Keeps the most recent clipboard entries in memory while clipboard history is on.
///
/// macOS posts no notification when the pasteboard changes, so this polls its
/// change count (a sub-microsecond local read) and reads contents only when the
/// count moves. The timer exists only while the feature is enabled, lets the
/// system coalesce its wakeups, and pauses while the screens sleep, the screen is
/// locked or another user's session is in front. Contents are read off the main
/// thread: the pasteboard server can stall for seconds (behind a password prompt,
/// say), and a blocked main thread would stall the media-key event tap with it.
@MainActor
final class ClipboardHistoryManager: ObservableObject {
    static let shared = ClipboardHistoryManager()

    @Published private(set) var items: [ClipboardItem] = []
    /// Set when "Paste from Other Apps" denies Boring Notch, so the UI can explain an empty history.
    @Published private(set) var isAccessDenied = false

    private static let pollInterval: TimeInterval = 1
    private static let pollTolerance: TimeInterval = 0.5

    private let pasteboardQueue = DispatchQueue(label: "theboringteam.boringnotch.clipboard", qos: .utility)
    private var timer: Timer?
    private var lastChangeCount = 0
    private var isReading = false
    private var isEnabled = false
    private var screensAsleep = false
    private var screenLocked = false
    private var sessionActive = true
    private var frontmostBundleIdentifier: String?
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// Starts following the clipboard-history settings. Call once at launch.
    func startObservingPreferences() {
        guard cancellables.isEmpty else { return }
        Defaults.publisher(.clipboardHistoryEnabled)
            .sink { [weak self] change in
                Task { @MainActor in self?.setEnabled(change.newValue) }
            }
            .store(in: &cancellables)
        Defaults.publisher(.clipboardHistoryLimit, options: [])
            .sink { [weak self] _ in
                Task { @MainActor in self?.trimToLimit() }
            }
            .store(in: &cancellables)
        observeSystemState()
    }

    /// Records the pasteboard contents if they changed since the last check.
    /// Also called when the Clipboard tab appears, so it never shows stale history.
    func checkNow() {
        check(source: frontmostBundleIdentifier)
    }

    /// Puts an entry back on the pasteboard and moves it to the front.
    func copy(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        items.insert(
            ClipboardItem(id: item.id, content: item.content, sourceBundleIdentifier: item.sourceBundleIdentifier),
            at: 0
        )
        let content = item.content
        pasteboardQueue.async { [weak self] in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            switch content {
            case .text(let text):
                pasteboard.setString(text, forType: .string)
            case .files(let urls):
                pasteboard.writeObjects(urls.map { $0 as NSURL })
            }
            let changeCount = pasteboard.changeCount
            Task { @MainActor in
                // Our own write shouldn't come back as a new entry.
                self?.lastChangeCount = changeCount
            }
        }
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }

    /// Opens System Settings → Privacy & Security → Paste from Other Apps.
    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Polling

    private var shouldPoll: Bool {
        isEnabled && !screensAsleep && !screenLocked && sessionActive
    }

    private func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            // Start from what's on the pasteboard now; only later copies are recorded.
            lastChangeCount = NSPasteboard.general.changeCount
            frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            Log.clipboard.notice("Clipboard history enabled")
        } else {
            items.removeAll()
            isAccessDenied = false
            Log.clipboard.notice("Clipboard history disabled; history cleared")
        }
        updatePolling()
    }

    private func updatePolling() {
        guard shouldPoll else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkNow() }
        }
        timer.tolerance = Self.pollTolerance
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Pick up anything copied while polling was paused.
        checkNow()
    }

    private func check(source: String?) {
        guard isEnabled, !isReading else { return }
        let changeCount = NSPasteboard.general.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        isReading = true
        pasteboardQueue.async { [weak self] in
            let result = ClipboardPasteboardReader.read(NSPasteboard.general)
            Task { @MainActor in
                self?.finishRead(result, source: source)
            }
        }
    }

    private func finishRead(_ result: ClipboardPasteboardReader.Result, source: String?) {
        isReading = false
        guard isEnabled else { return }
        switch result {
        case .content(let content):
            isAccessDenied = false
            record(content, source: source)
        case .skipped:
            isAccessDenied = false
        case .denied:
            if !isAccessDenied {
                Log.clipboard.notice("Pasteboard access denied in Privacy & Security settings")
            }
            isAccessDenied = true
        }
    }

    private func record(_ content: ClipboardItem.Content, source: String?) {
        // Re-copying the newest entry (our own writes included) changes nothing.
        guard items.first?.content != content else { return }
        items.removeAll { $0.content == content }
        items.insert(ClipboardItem(content: content, sourceBundleIdentifier: source), at: 0)
        trimToLimit()
        Log.clipboard.debug("Recorded clipboard entry; \(self.items.count) kept")
    }

    private func trimToLimit() {
        let limit = max(1, Defaults[.clipboardHistoryLimit])
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
    }

    // MARK: - System state

    private func observeSystemState() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionActive = false }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionActive = true }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }

        observers.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleIdentifier = app?.bundleIdentifier
            MainActor.assumeIsolated { self?.frontmostApplicationChanged(to: bundleIdentifier) }
        })
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        update: @escaping @MainActor @Sendable (ClipboardHistoryManager) -> Void
    ) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
                self.updatePolling()
            }
        })
    }

    private func frontmostApplicationChanged(to bundleIdentifier: String?) {
        // A copy made just before switching belongs to the app being left.
        check(source: frontmostBundleIdentifier)
        frontmostBundleIdentifier = bundleIdentifier
    }
}

/// Reads the general pasteboard. Called on the clipboard queue, never the main thread.
enum ClipboardPasteboardReader {
    enum Result {
        case content(ClipboardItem.Content)
        case skipped
        case denied
    }

    /// Password managers and similar apps mark secrets with these (nspasteboard.org conventions).
    private static let ignoredTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
    ]
    private static let maxTextLength = 1_000_000

    static func read(_ pasteboard: NSPasteboard) -> Result {
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny {
            return .denied
        }
        let types = pasteboard.types ?? []
        if types.contains(where: ignoredTypes.contains) {
            return .skipped
        }
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return .content(.files(urls))
        }
        if let text = pasteboard.string(forType: .string),
           text.utf16.count <= maxTextLength,
           !text.allSatisfy(\.isWhitespace) {
            return .content(.text(text))
        }
        return .skipped
    }
}
