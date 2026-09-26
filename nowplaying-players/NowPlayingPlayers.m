//
//  NowPlayingPlayers.m
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  Streams every app registered with macOS Now Playing, not only the one
//  macOS picked, for the Media tab's player pages. MediaRemote only answers
//  processes it trusts, so, like mediaremote-adapter, this is a library that
//  /usr/bin/perl loads (nowplaying-players.pl) rather than code in the app.
//
//  stdout, one JSON line whenever something changed:
//    {"elected": <pid of the Now Playing app, or null>,
//     "players": [{"id", "bundleIdentifier", "parentBundleIdentifier",
//                  "processIdentifier", "displayName", "isPlaying", "title",
//                  "artist", "album", "duration", "elapsedTime", "timestamp",
//                  "playbackRate", "artworkIdentifier", "artworkData"}, ...]}
//  "timestamp" is seconds since 1970 for "elapsedTime"; "artworkData"
//  (base64) is only sent when that player's artwork changed.
//
//  stdin: a line "refresh" asks for a fresh look; the end of input (the app
//  quit) ends the process.
//
//  Built by the app target's "Build Now Playing players helper" phase.
//

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

@interface NSObject (NowPlayingPlayersPrivate)
- (instancetype)initWithOrigin:(id)origin client:(id)client player:(id)player;
- (void)setArtworkWidth:(double)width;
- (void)setArtworkHeight:(double)height;
@end

// Errors stay raw pointers: they're never used, and ARC mustn't touch them.
typedef void (^ClientsReply)(NSArray *clients);
typedef void (^StateReply)(unsigned int state, void *error);
typedef void (^InfoReply)(NSDictionary *info, void *error);
typedef void (^PIDReply)(int pid);
typedef void (^QueueReply)(id playbackQueue, void *error);

static struct {
    void (*registerForNotifications)(dispatch_queue_t);
    void *(*localOrigin)(void);
    void (*clients)(dispatch_queue_t, ClientsReply);
    void *(*clientBundleIdentifier)(id);
    void *(*clientParentBundleIdentifier)(id);
    void *(*clientDisplayName)(id);
    int (*clientProcessIdentifier)(id);
    void (*playbackState)(id client, id origin, dispatch_queue_t, StateReply);
    void (*nowPlayingInfo)(id client, id origin, int, dispatch_queue_t, InfoReply);
    void (*nowPlayingPID)(dispatch_queue_t, PIDReply);
    void *(*createDefaultRequest)(void);
    void (*requestIncludeArtwork)(id, BOOL);
    void (*playbackQueueForPlayer)(id request, id playerPath, dispatch_queue_t, QueueReply);
    void *(*contentItemAtOffset)(id, long);
    void *(*contentItemArtworkData)(id);
} MR;

/// How long to wait for any one MediaRemote reply.
static const int64_t kReplyTimeout = 2 * NSEC_PER_SEC;
/// Notifications come in bursts (state, info and elected player at once).
static const double kRefreshDelay = 0.15;
/// Enough for the 120 pt art at 2x.
static const double kArtworkSize = 320;
/// How long after a track change its artwork is fetched again on each look,
/// and when the extra look after a change comes.
static const double kArtworkSettleTime = 3;
static const double kArtworkRecheckDelay = 1.2;

static dispatch_queue_t workQueue;
static dispatch_queue_t replyQueue;
/// Kept for the life of the process.
static dispatch_source_t inputSource;

static void scheduleRefresh(double delay);
static BOOL refreshScheduled;
static NSString *lastLine;
/// Per player: the track the artwork was fetched for, the artwork, and the
/// artwork identifier the app already has.
static NSMutableDictionary<NSString *, NSString *> *artworkTrack;
static NSMutableDictionary<NSString *, NSData *> *artworkData;
static NSMutableDictionary<NSString *, NSString *> *sentArtwork;
/// When each player last changed track: right after a change, a player may
/// still hand over the last track's artwork, so it's fetched again shortly.
static NSMutableDictionary<NSString *, NSDate *> *trackChanged;

static void *symbol(void *library, const char *name) {
    void *pointer = dlsym(library, name);
    if (!pointer) {
        fprintf(stderr, "nowplaying-players: missing %s\n", name);
        exit(2);
    }
    return pointer;
}

/// One of MediaRemote's exported NSString constants, which hold their own names.
static NSString *constant(void *library, const char *name) {
    void **pointer = dlsym(library, name);
    return pointer && *pointer ? (__bridge NSString *)*pointer : @(name);
}

static void loadMediaRemote(void) {
    void *library = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!library) {
        fprintf(stderr, "nowplaying-players: can't load MediaRemote\n");
        exit(2);
    }
    MR.registerForNotifications = symbol(library, "MRMediaRemoteRegisterForNowPlayingNotifications");
    MR.localOrigin = symbol(library, "MRMediaRemoteGetLocalOrigin");
    MR.clients = symbol(library, "MRMediaRemoteGetNowPlayingClients");
    MR.clientBundleIdentifier = symbol(library, "MRNowPlayingClientGetBundleIdentifier");
    MR.clientParentBundleIdentifier = symbol(library, "MRNowPlayingClientGetParentAppBundleIdentifier");
    MR.clientDisplayName = symbol(library, "MRNowPlayingClientGetDisplayName");
    MR.clientProcessIdentifier = symbol(library, "MRNowPlayingClientGetProcessIdentifier");
    MR.playbackState = symbol(library, "MRMediaRemoteGetPlaybackStateForClient");
    MR.nowPlayingInfo = symbol(library, "MRMediaRemoteGetNowPlayingInfoForClient");
    MR.nowPlayingPID = symbol(library, "MRMediaRemoteGetNowPlayingApplicationPID");
    MR.createDefaultRequest = symbol(library, "MRPlaybackQueueRequestCreateDefault");
    MR.requestIncludeArtwork = symbol(library, "MRPlaybackQueueRequestSetIncludeArtwork");
    MR.playbackQueueForPlayer = symbol(library, "MRMediaRemoteRequestNowPlayingPlaybackQueueForPlayer");
    MR.contentItemAtOffset = symbol(library, "MRPlaybackQueueGetContentItemAtOffset");
    MR.contentItemArtworkData = symbol(library, "MRContentItemGetArtworkData");
}

/// Runs `request`, which must call `done` exactly once, and waits for it.
static BOOL waitForReply(void (^request)(dispatch_block_t done)) {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    request(^{ dispatch_semaphore_signal(semaphore); });
    return dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, kReplyTimeout)) == 0;
}

static id jsonValue(id value) {
    if ([value isKindOfClass:NSNumber.class]) {
        double number = [value doubleValue];
        return isfinite(number) ? value : NSNull.null;
    }
    return [value isKindOfClass:NSString.class] ? value : NSNull.null;
}

static id jsonString(void *value) {
    NSString *string = (__bridge NSString *)value;
    return [string isKindOfClass:NSString.class] && string.length > 0 ? string : NSNull.null;
}

/// A short, stable name for artwork bytes (64-bit FNV-1a).
static NSString *artworkIdentifier(NSData *data) {
    uint64_t hash = 0xcbf29ce484222325ULL;
    const uint8_t *bytes = data.bytes;
    for (NSUInteger index = 0; index < data.length; index++) {
        hash = (hash ^ bytes[index]) * 0x100000001b3ULL;
    }
    return [NSString stringWithFormat:@"%016llx", hash];
}

static NSData *fetchArtwork(id client, id origin) {
    Class pathClass = NSClassFromString(@"MRPlayerPath");
    id path = pathClass ? [[pathClass alloc] initWithOrigin:origin client:client player:nil] : nil;
    id request = (__bridge_transfer id)MR.createDefaultRequest();
    if (!path || !request) {
        return nil;
    }
    MR.requestIncludeArtwork(request, YES);
    if ([request respondsToSelector:@selector(setArtworkWidth:)] && [request respondsToSelector:@selector(setArtworkHeight:)]) {
        [request setArtworkWidth:kArtworkSize];
        [request setArtworkHeight:kArtworkSize];
    }
    __block NSData *artwork = nil;
    waitForReply(^(dispatch_block_t done) {
        MR.playbackQueueForPlayer(request, path, replyQueue, ^(id playbackQueue, void *error) {
            id item = playbackQueue ? (__bridge id)MR.contentItemAtOffset(playbackQueue, 0) : nil;
            NSData *data = item ? (__bridge NSData *)MR.contentItemArtworkData(item) : nil;
            artwork = [data isKindOfClass:NSData.class] && data.length > 0 ? [data copy] : nil;
            done();
        });
    });
    return artwork;
}

static NSMutableDictionary *describePlayer(id client, id origin) {
    NSString *bundleIdentifier = jsonString(MR.clientBundleIdentifier(client));
    if (![bundleIdentifier isKindOfClass:NSString.class]) {
        return nil;
    }
    int processIdentifier = MR.clientProcessIdentifier(client);
    NSString *playerID = [NSString stringWithFormat:@"%@:%d", bundleIdentifier, processIdentifier];

    __block unsigned int state = 0;
    waitForReply(^(dispatch_block_t done) {
        MR.playbackState(client, origin, replyQueue, ^(unsigned int reply, void *error) {
            state = reply;
            done();
        });
    });
    __block NSDictionary *info = nil;
    waitForReply(^(dispatch_block_t done) {
        MR.nowPlayingInfo(client, origin, 0, replyQueue, ^(NSDictionary *reply, void *error) {
            info = [reply isKindOfClass:NSDictionary.class] ? [reply copy] : nil;
            done();
        });
    });

    static NSString *titleKey, *artistKey, *albumKey, *durationKey, *elapsedKey, *timestampKey, *rateKey;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *library = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        titleKey = constant(library, "kMRMediaRemoteNowPlayingInfoTitle");
        artistKey = constant(library, "kMRMediaRemoteNowPlayingInfoArtist");
        albumKey = constant(library, "kMRMediaRemoteNowPlayingInfoAlbum");
        durationKey = constant(library, "kMRMediaRemoteNowPlayingInfoDuration");
        elapsedKey = constant(library, "kMRMediaRemoteNowPlayingInfoElapsedTime");
        timestampKey = constant(library, "kMRMediaRemoteNowPlayingInfoTimestamp");
        rateKey = constant(library, "kMRMediaRemoteNowPlayingInfoPlaybackRate");
    });

    NSMutableDictionary *player = [NSMutableDictionary dictionary];
    player[@"id"] = playerID;
    player[@"bundleIdentifier"] = bundleIdentifier;
    player[@"parentBundleIdentifier"] = jsonString(MR.clientParentBundleIdentifier(client));
    player[@"processIdentifier"] = @(processIdentifier);
    player[@"displayName"] = jsonString(MR.clientDisplayName(client));
    // 1 is playing; paused, stopped and interrupted all count as not.
    player[@"isPlaying"] = state == 1 ? @YES : @NO;
    player[@"title"] = jsonValue(info[titleKey]);
    player[@"artist"] = jsonValue(info[artistKey]);
    player[@"album"] = jsonValue(info[albumKey]);
    player[@"duration"] = jsonValue(info[durationKey]);
    player[@"elapsedTime"] = jsonValue(info[elapsedKey]);
    player[@"playbackRate"] = jsonValue(info[rateKey]);
    id timestamp = info[timestampKey];
    player[@"timestamp"] = [timestamp isKindOfClass:NSDate.class] ? @([timestamp timeIntervalSince1970]) : NSNull.null;

    // Artwork is the one expensive part: fetched once per track, or again
    // while a track has none yet (players often add it after the title).
    NSString *track = [NSString stringWithFormat:@"%@\n%@\n%@\n%@", player[@"title"], player[@"artist"], player[@"album"], player[@"duration"]];
    if (![artworkTrack[playerID] isEqualToString:track]) {
        artworkTrack[playerID] = track;
        [artworkData removeObjectForKey:playerID];
        trackChanged[playerID] = [NSDate date];
    }
    NSDate *changed = trackChanged[playerID];
    BOOL settling = changed && -changed.timeIntervalSinceNow < kArtworkSettleTime;
    if ((!artworkData[playerID] || settling) && info[titleKey]) {
        NSData *artwork = fetchArtwork(client, origin);
        if (artwork) {
            artworkData[playerID] = artwork;
        }
    }
    NSData *artwork = artworkData[playerID];
    player[@"artworkIdentifier"] = artwork ? artworkIdentifier(artwork) : NSNull.null;
    return player;
}

static void emit(NSDictionary *message) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    if (!json) {
        return;
    }
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    if (fflush(stdout) != 0) {
        exit(0); // The app is gone.
    }
}

static void refresh(void) {
    id origin = (__bridge id)MR.localOrigin();
    __block NSArray *clients = @[];
    waitForReply(^(dispatch_block_t done) {
        MR.clients(replyQueue, ^(NSArray *reply) {
            clients = [reply isKindOfClass:NSArray.class] ? [reply copy] : @[];
            done();
        });
    });
    __block int electedPID = 0;
    waitForReply(^(dispatch_block_t done) {
        MR.nowPlayingPID(replyQueue, ^(int pid) {
            electedPID = pid;
            done();
        });
    });

    NSMutableArray *players = [NSMutableArray array];
    NSMutableSet *present = [NSMutableSet set];
    for (id client in clients) {
        @autoreleasepool {
            NSMutableDictionary *player = describePlayer(client, origin);
            if (player) {
                [players addObject:player];
                [present addObject:player[@"id"]];
            }
        }
    }
    for (NSString *playerID in artworkTrack.allKeys) {
        if (![present containsObject:playerID]) {
            [artworkTrack removeObjectForKey:playerID];
            [artworkData removeObjectForKey:playerID];
            [sentArtwork removeObjectForKey:playerID];
            [trackChanged removeObjectForKey:playerID];
        }
    }
    // A track that just changed gets one more look, for its own artwork.
    for (NSString *playerID in trackChanged.allKeys) {
        if (-trackChanged[playerID].timeIntervalSinceNow < kArtworkRecheckDelay) {
            scheduleRefresh(kArtworkRecheckDelay);
            break;
        }
    }

    // Unchanged players aren't news; new artwork always is.
    NSDictionary *message = @{@"elected": electedPID > 0 ? @(electedPID) : NSNull.null, @"players": players};
    NSData *summary = [NSJSONSerialization dataWithJSONObject:message options:NSJSONWritingSortedKeys error:nil];
    NSString *line = summary ? [[NSString alloc] initWithData:summary encoding:NSUTF8StringEncoding] : nil;
    BOOL newArtwork = NO;
    for (NSMutableDictionary *player in players) {
        NSString *playerID = player[@"id"];
        NSString *identifier = player[@"artworkIdentifier"];
        if (![identifier isKindOfClass:NSString.class]) {
            // The app lets a player's artwork go when it has none, so it
            // must be sent again when it's back, even if it's the same.
            [sentArtwork removeObjectForKey:playerID];
            continue;
        }
        if (![sentArtwork[playerID] isEqualToString:identifier]) {
            player[@"artworkData"] = [artworkData[playerID] base64EncodedStringWithOptions:0];
            sentArtwork[playerID] = identifier;
            newArtwork = YES;
        }
    }
    if (!newArtwork && line && [line isEqualToString:lastLine]) {
        return;
    }
    lastLine = line;
    emit(message);
}

static void scheduleRefresh(double delay) {
    dispatch_async(workQueue, ^{
        if (refreshScheduled) {
            return;
        }
        refreshScheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), workQueue, ^{
            refreshScheduled = NO;
            @autoreleasepool {
                refresh();
            }
        });
    });
}

static void watchStandardInput(void) {
    fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, workQueue);
    static NSMutableData *pending;
    pending = [NSMutableData data];
    dispatch_source_set_event_handler(source, ^{
        uint8_t buffer[512];
        ssize_t count = read(STDIN_FILENO, buffer, sizeof buffer);
        if (count == 0) {
            exit(0); // The app is gone.
        }
        if (count < 0) {
            return;
        }
        [pending appendBytes:buffer length:(NSUInteger)count];
        NSData *newline = [NSData dataWithBytes:"\n" length:1];
        NSRange lineBreak;
        while ((lineBreak = [pending rangeOfData:newline options:0 range:NSMakeRange(0, pending.length)]).location != NSNotFound) {
            NSData *lineData = [pending subdataWithRange:NSMakeRange(0, lineBreak.location)];
            [pending replaceBytesInRange:NSMakeRange(0, NSMaxRange(lineBreak)) withBytes:NULL length:0];
            NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
            if ([[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] isEqualToString:@"refresh"]) {
                scheduleRefresh(0);
            }
        }
    });
    dispatch_resume(source);
    inputSource = source;
}

static void observeNotifications(void) {
    void *library = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    MR.registerForNotifications(dispatch_get_main_queue());
    const char *names[] = {
        "kMRMediaRemotePlayerIsPlayingDidChangeNotification",
        "kMRMediaRemotePlayerPlaybackStateDidChangeNotification",
        "kMRMediaRemotePlayerNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteElectedPlayerDidChangeNotification",
    };
    for (size_t index = 0; index < sizeof names / sizeof names[0]; index++) {
        if (!dlsym(library, names[index])) {
            continue;
        }
        [NSNotificationCenter.defaultCenter addObserverForName:constant(library, names[index])
                                                        object:nil
                                                         queue:nil
                                                    usingBlock:^(NSNotification *notification) {
                                                        scheduleRefresh(kRefreshDelay);
                                                    }];
    }
}

/// The perl script's entry point: streams until the app goes away.
void nowplaying_players_stream(void) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOFBF, 1 << 16);
        loadMediaRemote();
        workQueue = dispatch_queue_create("boringNotch.NowPlayingPlayers", DISPATCH_QUEUE_SERIAL);
        replyQueue = dispatch_queue_create("boringNotch.NowPlayingPlayers.replies", DISPATCH_QUEUE_CONCURRENT);
        artworkTrack = [NSMutableDictionary dictionary];
        artworkData = [NSMutableDictionary dictionary];
        sentArtwork = [NSMutableDictionary dictionary];
        trackChanged = [NSMutableDictionary dictionary];

        if (getenv("NOWPLAYING_PLAYERS_ONCE")) {
            dispatch_sync(workQueue, ^{
                refresh();
            });
            return;
        }
        observeNotifications();
        watchStandardInput();
        scheduleRefresh(0);
    }
    CFRunLoopRun();
}
