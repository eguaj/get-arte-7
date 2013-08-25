#!/usr/bin/env perl -w

use strict;
use warnings;
use LWP::UserAgent;

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
    $outFile =~ s/\?.*$//i;
    $outFile = sprintf("%s.mp4", $outFile);
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

my ($arte_vp_url) = ($content =~ m|arte_vp_url="([^"]+)"|ms);
if( not defined $arte_vp_url ) {
    print STDERR sprintf("Could not find arte_vp_url!\n");
    exit( 2 );
}

$response = $agent->get($arte_vp_url);
if( ! $response->is_success ) {
    print STDERR sprintf("Error fetching arte_vp_url '%s': %s\n", $arte_vp_url, $response->status_line);
    exit( 3 );
}
$content = $response->content;

my ($url) = ($content =~ m|HTTP_REACH_EQ_1":.*?"url":"([^"]+)"|ms);
if( not defined $url ) {
    print STDERR sprintf("Could not find 'HTTP_REACH_EQ_1' URL!\n");
    exit( 4 );
}
my @cmd = ('wget', '-O', $outFile, '-c', '--no-use-server-timestamps', $url);
print STDERR sprintf("Fetching URL '%s' into file '%s'\n", $url, $outFile);
system(@cmd);
my $ret = $?;
if( $ret == -1 ) {
    print STDERR sprintf("Could not execute, or find, the 'wget' command\n");
    exit(1);
}

if( $ret != 0 ) {
    print STDERR sprintf("'%s' returned with error code '%s'\n", join(' ', @cmd), $ret);
}
exit( $ret );
