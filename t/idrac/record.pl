#!/usr/bin/env perl

# Records what one iDRAC answers over Redfish into t/fixtures/<name>/redfish.json,
# cleaned of what identifies the machine and its network, and prints what the
# design wants to know about the controller.
#
#   IDRAC_HOST=192.0.2.10 IDRAC_USERNAME=root IDRAC_PASSWORD=... \
#   IDRAC_SSL_FINGERPRINT='sha256$...' \
#     perl -Ilib -It/lib t/idrac/record.pl idrac8
#
# IDRAC_VERIFY_SSL=0 instead of the fingerprint accepts any certificate.
# The script only sends GET requests, apart from the login and the logout.
#
# The whole tree is walked, for the summary. Written are only the kinds of
# document the tests read, without their vendor sections and without the
# text of log messages; see iDRACRecorder and iDRACSanitize.

use strict;
use warnings;
use File::Path qw( make_path );
use JSON::MaybeXS;
use LWP::UserAgent;
use iDRACRecorder;
use iDRACSanitize;
use WWW::iDRAC::Redfish;

my $name = shift // '';
die "usage: $0 <name>, for example idrac7 or idrac8\n" unless $name =~ /\A[a-z0-9][a-z0-9-]*\z/;
defined $ENV{$_} && length $ENV{$_} or die "set $_\n" for qw( IDRAC_HOST IDRAC_USERNAME IDRAC_PASSWORD );

# only an explicit 0 turns the check off; an empty or mistyped value does not
my %ssl = ( $ENV{IDRAC_VERIFY_SSL} // '' ) eq '0' ? ( verify_hostname => 0, SSL_verify_mode => 0 ) : ( verify_hostname => 1 );
$ssl{SSL_fingerprint} = $ENV{IDRAC_SSL_FINGERPRINT} if $ENV{IDRAC_SSL_FINGERPRINT};
my $ua      = LWP::UserAgent->new( timeout => 60, keep_alive => 1, max_redirect => 0, ssl_opts => \%ssl );
my $base    = 'https://'.$ENV{IDRAC_HOST};
my $redfish = WWW::iDRAC::Redfish->new( base_url => $base, username => $ENV{IDRAC_USERNAME}, password => $ENV{IDRAC_PASSWORD}, ua => $ua );

# an iDRAC allows only a few sessions; end ours on Ctrl+C and on a TERM
# so a killed script does not pin a slot until the controller times it out
my $ended = 0;
my $end_session = sub { return if $ended; $ended++; eval { $redfish->logout }; exit 130 };
$SIG{INT}  = $SIG{TERM} = $end_session;

my $hello = $ua->get( $base.'/redfish/v1/' );
my $root  = $redfish->root;

my $recorder = iDRACRecorder->new( redfish => $redfish );
my $raw      = $recorder->record;
my $sessions = eval { $redfish->get('/redfish/v1/SessionService') } || {};
my $open     = eval { $redfish->get( $root->{Links}{Sessions}{'@odata.id'} ) } || {};
$redfish->logout;
$ended = 1;

my ( $host ) = $ENV{IDRAC_HOST} =~ /\A\[?([^\]]+?)\]?(?::[0-9]+)?\z/;
my $sanitizer = iDRACSanitize->new->hide( host => $host )->hide( user => $ENV{IDRAC_USERNAME} )->hide( secret => $ENV{IDRAC_PASSWORD} );
my $clean     = $sanitizer->sanitize($raw);
my @leaks     = $sanitizer->leaks($clean);
die "not written, the recording still holds:\n".join( '', map { "  $_\n" } @leaks ) if @leaks;

my $dir = 't/fixtures/'.$name;
make_path($dir);
open my $out, '>:raw', $dir.'/redfish.json' or die "cannot write $dir/redfish.json: $!\n";
print {$out} JSON::MaybeXS->new( utf8 => 1, canonical => 1, pretty => 1 )->encode($clean);
close $out or die "cannot write $dir/redfish.json: $!\n";

my @walked   = sort keys %{ $recorder->walked };
my @left_out = $recorder->left_out;
my %kinds;
$kinds{ $recorder->walked->{$_} }++ for @left_out;
my ( $system )  = grep { ref $_ eq 'HASH' && $_->{Actions} && $_->{Actions}{'#ComputerSystem.Reset'} } values %$raw;
my ( $manager ) = grep { ref $_ eq 'HASH' && defined $_->{FirmwareVersion} && $_->{Actions} && $_->{Actions}{'#Manager.Reset'} } values %$raw;
my $say = sub { printf "%-22s %s\n", $_[0].':', defined $_[1] && length $_[1] ? $_[1] : '(not reported)' };
$say->( 'fixture', $dir.'/redfish.json, '.keys(%$clean).' documents kept of '.@walked.' walked' );
$say->( 'left out', join ', ', map { $kinds{$_}.' '.$_ } sort keys %kinds );
$say->( 'STOPPED EARLY', $recorder->truncated.' addresses were not walked; what is missing below may only be unwalked' ) if $recorder->truncated;
$say->( 'TLS', join ' ', grep { defined } $hello->header('Client-SSL-Version'), $hello->header('Client-SSL-Cipher') );
$say->( 'Redfish version', $root->{RedfishVersion} );
$say->( 'server model', $system && $system->{Model} );
$say->( 'manager model', $manager && $manager->{Model} );
$say->( 'firmware', $manager && $manager->{FirmwareVersion} );
$say->( 'reset types', $system && join ' ', @{ $system->{Actions}{'#ComputerSystem.Reset'}{'ResetType@Redfish.AllowableValues'} || [] } );
$say->( 'session collection', $root->{Links}{Sessions}{'@odata.id'} );
$say->( 'session timeout', $sessions->{SessionTimeout} );
$say->( 'sessions open', $open->{'Members@odata.count'} );
$say->( 'log services', join ' ', grep { m{/LogServices/[^/]+\z} } @walked );
$say->( 'license documents', join ' ', grep { /licen[sc]e/i } @walked );
$say->( 'not walked', scalar( @{ $recorder->skipped } ).' paths' );
$say->( 'failed', join ' ', map { $_.' ('.( $recorder->failed->{$_} =~ /failed: ([0-9]{3})/ ? $1 : 'error' ).')' } sort keys %{ $recorder->failed } );
print "\nRead $dir/redfish.json before it is committed: it must not name your machine, your network or a person.\n",
  "The cleaning is a net, not a proof.\n";
