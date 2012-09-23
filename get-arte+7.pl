#!/usr/bin/env perl -w

use strict;
use warnings;
use LWP::UserAgent;
use Getopt::Long;

my $convert_to_mp4 = undef;
my $result = GetOptions(
    "mp4" => \$convert_to_mp4
    );

my $page_url = shift;
my $outFile = shift;

if( not defined $page_url ) {
    print STDERR "Usage:\n";
    print STDERR "\n";
    print STDERR "  $0 <page_url>\n";
    print STDERR "\n";
    exit( 0 );
}

if( not defined $outFile ) {
    ($outFile) = ($page_url =~ m|.*/([^/]+)$|);
    $outFile =~ s/\.[a-z0-9]+$//i;
    $outFile = sprintf("%s.flv", $outFile);
}

my $agent = new LWP::UserAgent();

my $response;
my $content;

$response = $agent->get($page_url);
if( ! $response->is_success ) {
    print STDERR sprintf("Error fetching '%s': %s\n", $page_url, $response->status_line);
    exit( 1 );
}
$content = $response->content;

my ($videorefFileUrl) = ($content =~ m|^\s*vars_player\.videorefFileUrl\s*=\s*"([^"]+)"\s*;\s*$|ms);

if( not defined $videorefFileUrl ) {
    print STDERR sprintf("Could not find videorefFileUrl!\n");
    exit( 2 );
}

print STDERR sprintf("videorefFileUrl = %s\n", $videorefFileUrl);

$response = $agent->get($videorefFileUrl);
if( ! $response->is_success ) {
    print STDERR sprintf("Error fetching videorefFileUrl '%s': %s\n", $videorefFileUrl, $response->status_line);
    exit( 3 );
}
$content = $response->content;

my ($videoFrUrl) = ($content =~ m|<video\s+lang="fr"\s+ref="([^"]+)"\s*/>|ms);
if( not defined $videoFrUrl ) {
    print STDERR sprintf("Could not find videoFrUrl!\n");
    exit( 4 );
}

print STDERR sprintf("videoFrUrl = '%s'\n", $videoFrUrl);

$response = $agent->get($videoFrUrl);
if( ! $response->is_success ) {
    print STDERR sprintf("Error fetching '%s': %s", $videoFrUrl, $response->status_line);
    exit( 5 );
}
$content = $response->content;

my ($videoUrl) = ($content =~ m|<url\s+quality="hd"\s*>\s*(rtmp://[^<]+)</url>|ms);
if( not defined $videoUrl ) {
    print STDERR sprintf("Could not find videoUrl!\n");
    exit( 6 );
}

print STDERR sprintf("Fetching videoUrl '%s' into file '%s'\n", $videoUrl, $outFile);

my @cmd = ('rtmpdump', '-r', $videoUrl, '-o', $outFile, '-e');
my $ret = 2;
while( $ret == 2 ) {
    system(@cmd);
    $ret = $?;
    if( $ret == -1 ) {
	print STDERR sprintf("Could not execute, or find, the 'rtmpdump' command!\n");
	exit(1);
    }
}

if( $ret != 0 ) {
	print STDERR sprintf("rtmpdump returned with error code '%s'\n", $ret);
	exit( $ret );
}

if( $convert_to_mp4 ) {
    (my $outFileMP4 = $outFile) =~ s/\.flv$/.mp4/;
    @cmd = ('ffmpeg', '-i', $outFile, '-acodec', 'copy', '-vcodec', 'copy', '-f', 'mp4', $outFileMP4);
    system(@cmd);
    $ret = $?;
    if( $ret != 0) {
	print STDERR sprintf("Could not convert '%s' to '%s'!\n", $outFile, $outFileMP4);
	unlink($outFile);
	exit($ret);
    }
    unlink($outFile);
}

exit(0);
