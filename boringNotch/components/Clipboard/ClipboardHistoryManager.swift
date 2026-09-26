//
//  ClipboardHistoryManager.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-25.
//

import AppKit
import Combine
import Defaults

/// Keeps the most recent clipboard entries while clipboard history is on, and
/// saves them so they're back after quitting, pausing the feature or a restart.
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
    private static let saveDelay: Duration = .seconds(1)

    private enum ReadOutcome {
        case content(ClipboardItem.Content)
        case skipped
        case denied
    }

    private let store: ClipboardHistoryStore
    private let pasteboardQueue = DispatchQueue(label: "theboringteam.boringnotch.clipboard.pasteboard", qos: .utility)
    /// Serializes all disk work, so image files are written and deleted in order.
    private let storageQueue = DispatchQueue(label: "theboringteam.boringnotch.clipboard.storage", qos: .utility)
    private var timer: Timer?
    private var saveTask: Task<Void, Never>?
    private var hasUnsavedChanges = false
    private var didStart = false
    private var didLoad = false
    private var thumbnails: [String: NSImage] = [:]
    private var lastChangeCount = 0
    private var isReading = false
    private var isEnabled = false
    private var screensAsleep = false
    private var screenLocked = false
    private var sessionActive = true
    private var frontmostBundleIdentifier: String?
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []

    private init(store: ClipboardHistoryStore = .standard) {
        self.store = store
    }

    /// Loads the saved history, then starts following the settings. Call once at launch.
    func startObservingPreferences() {
        guard !didStart else { return }
        didStart = true
        let store = store
        storageQueue.async { [weak self] in
            let saved = store.load()
            Task { @MainActor in
                guard let self else { return }
                // Recording starts only once the saved history is back in place.
                self.items = saved
                self.didLoad = true
                self.updateItems { _ in }
                self.observePreferences()
                self.observeSystemState()
            }
        }
    }

    /// Records the pasteboard contents if they changed since the last check.
    /// Also called when the Clipboard tab appears, so it never shows stale history.
    func checkNow() {
        check(source: frontmostBundleIdentifier)
    }

    /// Puts an entry back on the pasteboard and moves it to the front.
    func copy(_ item: ClipboardItem) {
        updateItems { items in
            items.removeAll { $0.id == item.id }
            items.insert(
                ClipboardItem(id: item.id, content: item.content, sourceBundleIdentifier: item.sourceBundleIdentifier),
                at: 0
            )
        }
        let content = item.content
        let store = store
        pasteboardQueue.async { [weak self] in
            let pasteboard = NSPasteboard.general
            switch content {
            case .text(let text):
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            case .files(let urls):
                pasteboard.clearContents()
                pasteboard.writeObjects(urls.map { $0 as NSURL })
            case .image(let image):
                guard let png = try? Data(contentsOf: store.imageURL(for: image)) else {
                    Log.clipboard.error("A saved clipboard image is missing")
                    return
                }
                pasteboard.clearContents()
                pasteboard.setData(png, forType: .png)
                // Older apps only take TIFF.
                if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
                    pasteboard.setData(tiff, forType: .tiff)
                }
            }
            let changeCount = pasteboard.changeCount
            Task { @MainActor in
                // Our own write shouldn't come back as a new entry.
                self?.lastChangeCount = changeCount
            }
        }
    }

    func remove(_ item: ClipboardItem) {
        updateItems { $0.removeAll { $0.id == item.id } }
    }

    /// Deletes the whole history, saved copy and images included.
    func clear() {
        updateItems { $0.removeAll() }
    }

    func thumbnail(for image: ClipboardImage) -> NSImage? {
        if let cached = thumbnails[image.hash] {
            return cached
        }
        guard let thumbnail = NSImage(contentsOf: store.thumbnailURL(for: image)) else {
            return nil
        }
        thumbnails[image.hash] = thumbnail
        return thumbnail
    }

    /// Writes pending changes right away; called when the app quits.
    func flushSync() {
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedChanges else { return }
        hasUnsavedChanges = false
        let snapshot = items
        let store = store
        storageQueue.sync {
            try? store.save(snapshot)
        }
    }

    /// Opens System Settings → Privacy & Security → Paste from Other Apps.
    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - History and saving

    /// Applies a change, trims to the limit, deletes image files nothing uses
    /// anymore and saves shortly after.
    private func updateItems(_ change: (inout [ClipboardItem]) -> Void) {
        let before = items
        change(&items)
        let limit = max(1, Defaults[.clipboardHistoryLimit])
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
        let unused = Set(before.compactMap { $0.image?.hash }).subtracting(items.compactMap { $0.image?.hash })
        if !unused.isEmpty {
            unused.forEach { thumbnails[$0] = nil }
            let store = store
            storageQueue.async { store.removeImageFiles(for: unused) }
        }
        if items != before {
            scheduleSave()
        }
    }

    private func scheduleSave() {
        guard didLoad else { return }
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        guard hasUnsavedChanges else { return }
        hasUnsavedChanges = false
        let snapshot = items
        let store = store
        storageQueue.async {
            do {
                try store.save(snapshot)
            } catch {
                Log.clipboard.error("Couldn't save clipboard history: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func record(_ content: ClipboardItem.Content, source: String?) {
        // Re-copying the newest entry (our own writes included) changes nothing.
        guard items.first?.content != content else { return }
        updateItems { items in
            items.removeAll { $0.content == content }
            items.insert(ClipboardItem(content: content, sourceBundleIdentifier: source), at: 0)
        }
        Log.clipboard.debug("Recorded clipboard entry; \(self.items.count) kept")
    }

    // MARK: - Polling

    private var shouldPoll: Bool {
        isEnabled && !screensAsleep && !screenLocked && sessionActive
    }

    private func observePreferences() {
        Defaults.publisher(.clipboardHistoryEnabled)
            .sink { [weak self] change in
                Task { @MainActor in self?.setEnabled(change.newValue) }
            }
            .store(in: &cancellables)
        Defaults.publisher(.clipboardHistoryLimit, options: [])
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateItems { _ in } }
            }
            .store(in: &cancellables)
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
            // The saved history stays: turning the feature back on brings it back.
            isAccessDenied = false
            Log.clipboard.notice("Clipboard history paused")
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
        let store = store
        let storageQueue = storageQueue
        pasteboardQueue.async { [weak self] in
            let outcome: ReadOutcome
            switch ClipboardPasteboardReader.read(NSPasteboard.general) {
            case .content(let content):
                outcome = .content(content)
            case .denied:
                outcome = .denied
            case .skipped:
                let types = (NSPasteboard.general.types ?? []).map(\.rawValue)
                Log.clipboard.debug("Skipped a copy with types \(types, privacy: .public)")
                outcome = .skipped
            case .image(let data):
                // Image files are written on the storage queue, in order with deletions.
                storageQueue.async { [weak self] in
                    let outcome: ReadOutcome
                    do {
                        outcome = .content(.image(try store.saveImage(data)))
                    } catch {
                        Log.clipboard.error("Couldn't save a copied image: \(error.localizedDescription, privacy: .public)")
                        outcome = .skipped
                    }
                    Task { @MainActor in self?.finishRead(outcome, source: source) }
                }
                return
            }
            Task { @MainActor in self?.finishRead(outcome, source: source) }
        }
    }

    private func finishRead(_ outcome: ReadOutcome, source: String?) {
        isReading = false
        guard isEnabled else { return }
        switch outcome {
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
