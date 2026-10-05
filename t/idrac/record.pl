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

my %ssl = ( $ENV{IDRAC_VERIFY_SSL} // 1 ) ? ( verify_hostname => 1 ) : ( verify_hostname => 0, SSL_verify_mode => 0 );
$ssl{SSL_fingerprint} = $ENV{IDRAC_SSL_FINGERPRINT} if $ENV{IDRAC_SSL_FINGERPRINT};
my $ua      = LWP::UserAgent->new( timeout => 60, keep_alive => 1, ssl_opts => \%ssl );
my $base    = 'https://'.$ENV{IDRAC_HOST};
my $redfish = WWW::iDRAC::Redfish->new( base_url => $base, username => $ENV{IDRAC_USERNAME}, password => $ENV{IDRAC_PASSWORD}, ua => $ua );

my $hello = $ua->get( $base.'/redfish/v1/' );
my $root  = $redfish->root;

my $recorder = iDRACRecorder->new( redfish => $redfish );
my $raw      = $recorder->record;
my $sessions = eval { $redfish->get('/redfish/v1/SessionService') } || {};
my $open     = eval { $redfish->get( $root->{Links}{Sessions}{'@odata.id'} ) } || {};
$redfish->logout;

my ( $host ) = $ENV{IDRAC_HOST} =~ /\A\[?([^\]]+?)\]?(?::[0-9]+)?\z/;
my $clean = iDRACSanitize->new->hide( host => $host )->hide( user => $ENV{IDRAC_USERNAME} )->sanitize($raw);
my @leaks = iDRACSanitize->leaks( $clean, $host, $ENV{IDRAC_PASSWORD}, ( map { $_->{SKU}, $_->{SerialNumber} } grep { ref $_ eq 'HASH' } values %$raw ) );
die 'not written, these values are still in the recording: '.join( ', ', @leaks )."\n" if @leaks;

my $dir = 't/fixtures/'.$name;
make_path($dir);
open my $out, '>:raw', $dir.'/redfish.json' or die "cannot write $dir/redfish.json: $!\n";
print {$out} JSON::MaybeXS->new( utf8 => 1, canonical => 1, pretty => 1 )->encode($clean);
close $out or die "cannot write $dir/redfish.json: $!\n";

my ( $system )  = grep { ref $_ eq 'HASH' && $_->{Actions} && $_->{Actions}{'#ComputerSystem.Reset'} } values %$raw;
my ( $manager ) = grep { ref $_ eq 'HASH' && defined $_->{FirmwareVersion} && $_->{Actions} && $_->{Actions}{'#Manager.Reset'} } values %$raw;
my $say = sub { printf "%-22s %s\n", $_[0].':', defined $_[1] && length $_[1] ? $_[1] : '(not reported)' };
$say->( 'fixture', $dir.'/redfish.json, '.keys(%$clean).' documents' );
$say->( 'TLS', join ' ', grep { defined } $hello->header('Client-SSL-Version'), $hello->header('Client-SSL-Cipher') );
$say->( 'Redfish version', $root->{RedfishVersion} );
$say->( 'server model', $system && $system->{Model} );
$say->( 'manager model', $manager && $manager->{Model} );
$say->( 'firmware', $manager && $manager->{FirmwareVersion} );
$say->( 'reset types', $system && join ' ', @{ $system->{Actions}{'#ComputerSystem.Reset'}{'ResetType@Redfish.AllowableValues'} || [] } );
$say->( 'session collection', $root->{Links}{Sessions}{'@odata.id'} );
$say->( 'session timeout', $sessions->{SessionTimeout} );
$say->( 'sessions open', $open->{'Members@odata.count'} );
$say->( 'log services', join ' ', sort grep { m{/LogServices/[^/]+\z} } keys %$raw );
$say->( 'license documents', join ' ', sort grep { /licen[sc]e/i } keys %$raw );
$say->( 'not walked', scalar( @{ $recorder->skipped } ).' paths' );
$say->( 'failed', join ' ', map { $_.' ('.( $recorder->failed->{$_} =~ /failed: ([0-9]{3})/ ? $1 : 'error' ).')' } sort keys %{ $recorder->failed } );
print "\nRead $dir/redfish.json before it is committed: it must not name your machine, your network or a person.\n";
