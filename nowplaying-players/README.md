# nowplaying-players

A small helper that lists **every** app registered with macOS Now Playing, not
only the one macOS elected, for the Media tab's pages of other players
(`boringNotch/components/MediaPlayers/`).

## Why a helper

`MediaRemote.framework` only answers processes it trusts. Like
[mediaremote-adapter](../mediaremote-adapter/README.md), which the notch uses for
the elected player, this is a library that `/usr/bin/perl` loads:
`NowPlayingPlayersService` spawns `/usr/bin/perl nowplaying-players.pl NowPlayingPlayers.dylib`
and reads JSON lines from it. Called from the app itself, the same MediaRemote
functions return nothing.

The upstream adapter (v0.7.7) can't do this: it only reports the elected player.

## What it sends

One line on stdout whenever something changed:

```json
{"elected": 66395,
 "players": [{"id": "com.apple.Music:66395", "bundleIdentifier": "com.apple.Music",
              "parentBundleIdentifier": null, "processIdentifier": 66395,
              "displayName": "Music", "isPlaying": true, "title": "First Class",
              "artist": "Khruangbin", "album": "Mordechai", "duration": 287.04,
              "elapsedTime": 1.9, "timestamp": 1790440710.97, "playbackRate": 1,
              "artworkIdentifier": "909f11df01084052", "artworkData": "<base64>"}]}
```

- `elected` is the pid of the Now Playing app; `timestamp` (seconds since 1970)
  is when `elapsedTime` was measured.
- Artwork comes from a playback-queue request at 320 px, fetched once per track,
  and `artworkData` is only sent when a player's artwork changed.
- It waits for MediaRemote's player notifications, coalesced over 150 ms; it
  never polls. A line `refresh` on stdin asks for a fresh look (the Media tab
  sends one when it appears), and the end of stdin (the app quit) ends it.

## Building

The app target's **Build Now Playing players helper** phase compiles
`NowPlayingPlayers.m` for the app's architectures, signs it with the build's
identity, and copies it and `nowplaying-players.pl` into `Contents/Resources`.
Nothing is checked in as a binary.

To see what it reports, build it by hand and print one line:

```sh
xcrun clang -fobjc-arc -dynamiclib -framework Foundation \
    nowplaying-players/NowPlayingPlayers.m -o /tmp/NowPlayingPlayers.dylib
NOWPLAYING_PLAYERS_ONCE=1 /usr/bin/perl nowplaying-players/nowplaying-players.pl /tmp/NowPlayingPlayers.dylib
```

## MediaRemote functions used

All private, resolved with `dlsym`, signatures read from the disassembly on
macOS 27: `MRMediaRemoteGetNowPlayingClients`, `MRNowPlayingClientGet*`,
`MRMediaRemoteGetPlaybackStateForClient(client, origin, queue, block)`,
`MRMediaRemoteGetNowPlayingInfoForClient(client, origin, flag, queue, block)`,
`MRMediaRemoteGetNowPlayingApplicationPID`, and for artwork
`MRPlaybackQueueRequestCreateDefault` + `MRPlaybackQueueRequestSetIncludeArtwork`
+ `MRMediaRemoteRequestNowPlayingPlaybackQueueForPlayer(request, playerPath, queue, block)`
+ `MRContentItemGetArtworkData`, with the player path made by
`-[MRPlayerPath initWithOrigin:client:player:]`.
