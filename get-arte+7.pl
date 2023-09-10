#!/usr/bin/env perl -w

use strict;
use warnings;

use Mozilla::CA;
use LWP::UserAgent;
use List::Util qw(any);
use File::Basename qw(dirname basename);
use JSON::PP qw(decode_json);

my $dryRun = 0;
my $videoQuality = 720;
while (scalar @ARGV > 0) {
    if ($ARGV[0] eq '--help' or $ARGV[0] eq '-h') {
        usage();
        exit(0);
    } elsif ($ARGV[0] eq "--dry-run") {
        $dryRun = 1;
        shift;
    } elsif ($ARGV[0] eq "--videoQuality") {
        shift;
        $videoQuality = $ARGV[0];
        shift;
    } elsif ($ARGV[0] eq "--") {
        shift;
        last;
    } else {
        last;
    }
}

my $pageUrl = shift;
my $outFile = shift;

sub usage {
    print STDERR "Usage:\n";
    print STDERR "\n";
    print STDERR "  $0 [options] <pageUrl> [<outputFile>]\n";
    print STDERR "\n";
    print STDERR "Options:\n";
    print STDERR "  --dry-run                     Fetch/parse URLs but do not download medias\n";
    print STDERR "  --videoQuality <quality>      Video quality (e.g. '720', '1080', etc.)(default is '720')\n";
    print STDERR "\n";
}

if (not defined $pageUrl) {
    usage();
    exit(0);
}

if (not defined $outFile) {
    ($outFile) = ($pageUrl =~ m|.*/([^/]+)/?$|);
    if (not defined $outFile) {
        print STDERR sprintf("Error: could compute output filename from page URL '%s'!\n", $pageUrl);
        exit(1);
    }
    $outFile =~ s/\?.*$//i;
    $outFile = sprintf("%s.mp4", $outFile);
    printf("Output to '%s'\n", $outFile);
}

my ($videoId) = ($pageUrl =~ m|.*/videos/([^/]+)/.*|);
if (not defined $videoId) {
    print STDERR sprintf("Error: could not get videoId from page URL '%s'!\n", $pageUrl);
    exit(1);
}
printf("videoId = %s\n", $videoId);
my $apiPlayerUrl = sprintf("https://api.arte.tv/api/player/v2/config/fr/%s", $videoId);
printf("apiPlayerUrl = %s\n", $apiPlayerUrl);

my $agent = new LWP::UserAgent();
my $response;
my $content;

$response = $agent->get($apiPlayerUrl);
if (!$response->is_success) {
    print STDERR sprintf("Error: could not fetch '%s': %s\n", $pageUrl, $response->status_line);
    exit( 1 );
}
if (! eval { $content = decode_json($response->content); 1; }) {
    print STDERR sprintf("Error: could not decode JSON from '%s'!\n", $apiPlayerUrl);
    exit(1);
}

my $m3u8Url = undef;
if (not defined $content->{'data'}->{'attributes'}->{'streams'}) {
    print STDERR sprintf("Error: could not find stream in JSON from '%s'!\n", $apiPlayerUrl);
    exit(1);
}
my $streams = $content->{'data'}->{'attributes'}->{'streams'};
for my $stream (@{$streams}) {
    if (defined $stream->{'versions'}[0]->{'shortLabel'} and any { $_ eq $stream->{'versions'}[0]->{'shortLabel'} } @{['VOF', 'VF']}) {
        $m3u8Url = $stream->{'url'};
        last;
    }
}
if (not defined $m3u8Url) {
    print STDERR sprintf("Error: could not find m3u8 URL in JSON from '%s'!\n", $apiPlayerUrl);
    exit(1);
}
printf("m3u8Url = %s\n", $m3u8Url);
my ($baseUrl) = dirname($m3u8Url);
printf("baseUrl = %s\n", $baseUrl);

$response = $agent->get($m3u8Url);
if (!$response->is_success) {
    print STDERR sprintf("Error: could not fetch '%s': %s\n", $m3u8Url, $response->status_line);
    exit(1);
}
$content = $response->content;

my ($videoUrl) = ($content =~ m|^(medias/[^.]+_v\Q${videoQuality}\E)\.m3u8$|m);
if (not defined $videoUrl) {
    print STDERR sprintf("Error: could not find video URL with quality '%s'!\n", $videoQuality);
    exit(1);
}
$videoUrl = sprintf("%s/%s.mp4", $baseUrl, $videoUrl);
printf("videoUrl = %s\n", $videoUrl);

my ($audioUrl) = ($content =~ m|\bTYPE=AUDIO\b.*?\bURI="(medias/[^"]+)\.m3u8"|m);
if (not defined $audioUrl) {
    print STDERR sprintf("Error: could not find audio URL!\n");
    exit(1);
}
$audioUrl = sprintf("%s/%s.mp4", $baseUrl, $audioUrl);
printf("audioUrl = %s\n", $audioUrl);

my $audioFile = sprintf("%s.audio", basename($audioUrl));
my $videoFile = sprintf("%s.video", basename($videoUrl));

my (@cmd, $ret);

@cmd = ('curl', '-o', $audioFile, '-C', '-', $audioUrl);
printf("Downloading audio '%s' into file '%s'\n", $audioUrl, $audioFile);
if (!$dryRun) {
    system(@cmd);
    $ret = $?;
    if ($ret == -1) {
        print STDERR sprintf("Error: could not execute, or find, the 'curl' command!\n");
        exit(1);
    }
    if ($ret != 0) {
        print STDERR sprintf("Error: '%s' returned with error code '%s'\n", join(' ', @cmd), $ret);
        exit(1);
    }
}

@cmd = ('curl', '-o', $videoFile, '-C', '-', $videoUrl);
printf("Downloading video '%s' into file '%s'\n", $videoUrl, $videoFile);
if (!$dryRun) {
    system(@cmd);
    $ret = $?;
    if( $ret == -1 ) {
        print STDERR sprintf("Error: could not execute, or find, the 'curl' command!\n");
        exit(1);
    }
    if ($ret != 0) {
        print STDERR sprintf("Error: '%s' returned with error code '%s'\n", join(' ', @cmd), $ret);
        exit(1);
    }
}

@cmd = ('ffmpeg', '-i', $videoFile, '-i', $audioFile, '-c:v', 'copy', '-c:a', 'copy', $outFile);
printf("Merging audio '%s' and video '%s' into '%s'\n", $audioFile, $videoFile, $outFile);
if (!$dryRun) {
    system(@cmd);
    $ret = $?;
    if( $ret == -1 ) {
        print STDERR sprintf("Error: could not execute, or find, the 'ffmpeg' command!\n");
        exit(1);
    }
    if( $ret != 0 ) {
        print STDERR sprintf("Error: '%s' returned with error code '%s'\n", join(' ', @cmd), $ret);
        exit(1);
    }

    unlink($audioFile);
    unlink($videoFile);
}

exit(0);