//
//  NowPlayingPlayersService.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  Runs the nowplaying-players helper, /usr/bin/perl loading
//  NowPlayingPlayers.dylib the way NowPlayingController runs
//  mediaremote-adapter, and publishes every player other than the live one
//  for the Media tab's pages.
//

import AppKit
import Combine
import Defaults

/// A player's artwork, with the color the tinting options use.
struct MediaPlayerArtwork: Equatable {
    let identifier: String
    let image: NSImage
    var averageColor: NSColor?

    static func == (lhs: MediaPlayerArtwork, rhs: MediaPlayerArtwork) -> Bool {
        lhs.identifier == rhs.identifier && lhs.averageColor == rhs.averageColor
    }
}

@MainActor
final class NowPlayingPlayersService: ObservableObject {
    static let shared = NowPlayingPlayersService()

    /// The pages after the live one, in order (see MediaPlayerLineup).
    @Published private(set) var otherPlayers: [MediaPlayerSnapshot] = []
    /// The app macOS elected as Now Playing, which the live page shows.
    @Published private(set) var electedProcessIdentifier: Int32?
    /// By player ID.
    @Published private(set) var artwork: [String: MediaPlayerArtwork] = [:]

    var hasOtherPlayers: Bool { !otherPlayers.isEmpty }

    /// A helper that keeps failing is left off for this long.
    private static let failureCooldown: TimeInterval = 60

    private var lineup = MediaPlayerLineup()
    private var snapshots: [MediaPlayerSnapshot] = []
    private var livePage = MediaPlayerLineup.LivePage(bundleIdentifier: nil, title: "")
    private var isWanted = false
    private var wasRequested = false
    private var process: Process?
    private var input: FileHandle?
    private var output: HelperOutputReader?
    private var restartTask: Task<Void, Never>?
    /// Tells a session's late callbacks apart from the current session's.
    private var generation = 0
    private var failures: [Date] = []
    private var appNames: [String: String] = [:]
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let music = MusicManager.shared
        music.$effectiveMediaController
            .combineLatest(Defaults.publisher(.mediaPlayerPages).map(\.newValue))
            .map { controller, enabled in controller == .nowPlaying && enabled }
            .removeDuplicates()
            .sink { [weak self] wanted in
                self?.setWanted(wanted)
            }
            .store(in: &cancellables)
        // The live page hides its own player from the others. @Published
        // sends the new values before MusicManager holds them, so they're
        // taken from here rather than read back.
        music.$bundleIdentifier
            .combineLatest(music.$songTitle)
            .sink { [weak self] bundleIdentifier, title in
                self?.livePage = MediaPlayerLineup.LivePage(bundleIdentifier: bundleIdentifier, title: title)
                self?.updateLineup()
            }
            .store(in: &cancellables)
    }

    /// The Media tab asks for a fresh look whenever it appears; the first
    /// time also starts the helper, so nothing runs before it's needed.
    func refresh() {
        wasRequested = true
        guard isWanted else { return }
        if process != nil {
            send("refresh")
        } else {
            start()
        }
    }

    /// After a command to a player, whose state macOS reports a moment later.
    func refresh(after delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.refresh()
        }
    }

    func appName(for bundleIdentifier: String) -> String? {
        if let name = appNames[bundleIdentifier] {
            return name
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let name = try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName
        else {
            return nil
        }
        appNames[bundleIdentifier] = name
        return name
    }

    // MARK: - Helper process

    private func setWanted(_ wanted: Bool) {
        isWanted = wanted
        if wanted {
            if wasRequested {
                start()
            }
        } else {
            stop()
        }
    }

    private func start() {
        guard process == nil, restartTask == nil else { return }
        failures = failures.filter { -$0.timeIntervalSinceNow < Self.failureCooldown }
        guard failures.count < 3 else { return }
        guard let script = Bundle.main.url(forResource: "nowplaying-players", withExtension: "pl"),
              let library = Bundle.main.url(forResource: "NowPlayingPlayers", withExtension: "dylib")
        else {
            Log.music.error("The Now Playing players helper is missing from the app")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, library.path]
        let input = Pipe()
        // Writing to a helper that died must fail, not kill the app with SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let outputPipe = Pipe()
        process.standardInput = input
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        generation += 1
        let generation = generation
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor [weak self] in
                self?.helperEnded(generation: generation, status: status)
            }
        }
        do {
            try process.run()
        } catch {
            Log.music.error("Couldn't start the Now Playing players helper: \(error.localizedDescription, privacy: .public)")
            return
        }
        self.process = process
        self.input = input.fileHandleForWriting
        output = HelperOutputReader(handle: outputPipe.fileHandleForReading) { [weak self] line in
            guard let message = try? JSONDecoder().decode(NowPlayingPlayersMessage.self, from: line) else { return }
            let decoded = DecodedMessage(message)
            Task { @MainActor [weak self] in
                self?.apply(decoded, generation: generation)
            }
        }
        Log.music.notice("Started the Now Playing players helper")
    }

    private func stop() {
        generation += 1
        restartTask?.cancel()
        restartTask = nil
        // Closing its input ends the helper; terminate covers a stuck one.
        try? input?.close()
        output?.close()
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        input = nil
        output = nil
        snapshots = []
        lineup = MediaPlayerLineup()
        if electedProcessIdentifier != nil { electedProcessIdentifier = nil }
        if !otherPlayers.isEmpty { otherPlayers = [] }
        if !artwork.isEmpty { artwork = [:] }
    }

    private func helperEnded(generation: Int, status: Int32) {
        guard generation == self.generation else { return }
        Log.music.error("The Now Playing players helper stopped (status \(status)); restarting it")
        stop()
        failures.append(Date())
        guard isWanted else { return }
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.restartTask = nil
            self.start()
        }
    }

    private func send(_ line: String) {
        try? input?.write(contentsOf: Data((line + "\n").utf8))
    }

    // MARK: - Updates

    private func apply(_ message: DecodedMessage, generation: Int) {
        guard generation == self.generation else { return }
        if electedProcessIdentifier != message.elected {
            electedProcessIdentifier = message.elected
        }
        snapshots = message.players

        var artwork = self.artwork
        let current = Dictionary(message.players.map { ($0.id, $0.artworkIdentifier) }, uniquingKeysWith: { first, _ in first })
        artwork = artwork.filter { id, art in current[id] == art.identifier }
        for update in message.artwork {
            guard let image = NSImage(data: update.data) else { continue }
            artwork[update.playerID] = MediaPlayerArtwork(identifier: update.identifier, image: image)
            findAverageColor(of: image, for: update.playerID, identifier: update.identifier)
        }
        if artwork != self.artwork {
            self.artwork = artwork
        }
        updateLineup()
    }

    private func findAverageColor(of image: NSImage, for playerID: String, identifier: String) {
        Task { [weak self, image] in
            let color = await image.averageColor()
            guard let self, self.artwork[playerID]?.identifier == identifier else { return }
            self.artwork[playerID]?.averageColor = color
        }
    }

    private func updateLineup() {
        lineup.update(with: snapshots, elected: electedProcessIdentifier, live: livePage)
        if lineup.players != otherPlayers {
            if lineup.players.count != otherPlayers.count {
                let apps = lineup.players.map(\.appBundleIdentifier).joined(separator: ", ")
                Log.music.info("Players with a page of their own: \(apps, privacy: .public)")
            }
            otherPlayers = lineup.players
        }
    }
}

/// A helper line with its artwork already decoded, off the main actor.
private struct DecodedMessage: Sendable {
    struct Artwork: Sendable {
        let playerID: String
        let identifier: String
        let data: Data
    }

    let elected: Int32?
    let players: [MediaPlayerSnapshot]
    let artwork: [Artwork]

    init(_ message: NowPlayingPlayersMessage) {
        elected = message.elected
        players = message.players.map(\.snapshot)
        artwork = message.players.compactMap { player in
            guard let identifier = player.artworkIdentifier,
                  let encoded = player.artworkData,
                  let data = Data(base64Encoded: encoded)
            else {
                return nil
            }
            return Artwork(playerID: player.id, identifier: identifier, data: data)
        }
    }
}

/// Reads the helper's JSON lines as they arrive. Deliberately not with
/// JSONLinesPipeHandler: FileHandle.AsyncBytes reads block on one serial
/// queue that every AsyncBytes reader in the app shares, so this pipe sitting
/// idle held up the Now Playing adapter's stream (and with it the live page
/// and One player at a time) until the helper next printed something:
/// seconds, or for good. A readability handler only reads when there's data.
private final class HelperOutputReader: @unchecked Sendable {
    private let handle: FileHandle
    /// Only touched by the readability handler, which runs one call at a time.
    private var pending = Data()

    init(handle: FileHandle, onLine: @escaping @Sendable (Data) -> Void) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else {
                // The end of the output: the helper has gone.
                handle.readabilityHandler = nil
                return
            }
            self.pending.append(chunk)
            while let newline = self.pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = self.pending.subdata(in: self.pending.startIndex..<newline)
                self.pending.removeSubrange(self.pending.startIndex...newline)
                if !line.isEmpty {
                    onLine(line)
                }
            }
        }
    }

    func close() {
        handle.readabilityHandler = nil
        try? handle.close()
    }
}
