#!/usr/bin/perl
# Loads NowPlayingPlayers.dylib and streams every app registered with macOS
# Now Playing as JSON lines (see NowPlayingPlayers.m). MediaRemote only
# answers processes it trusts, which /usr/bin/perl is, so the library runs
# inside perl, the way mediaremote-adapter.pl runs its framework.
#
# Usage: nowplaying-players.pl LIBRARY
#   NOWPLAYING_PLAYERS_ONCE=1 prints a single line and exits.
use strict;
use warnings;
use DynaLoader;

my $library = shift @ARGV or die "Usage: nowplaying-players.pl LIBRARY\n";
my $handle = DynaLoader::dl_load_file($library, 0) or die "Can't load $library\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "nowplaying_players_stream")
  or die "No nowplaying_players_stream in $library\n";
DynaLoader::dl_install_xsub("main::stream", $symbol);
stream();
