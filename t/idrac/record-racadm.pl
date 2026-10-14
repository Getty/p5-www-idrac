#!/usr/bin/env perl

# Records what one iDRAC prints for the reading racadm commands the classes
# Bios, Jobs, VirtualMedia and Capabilities send, into
# t/fixtures/<name>/racadm.json, cleaned of what identifies the machine and
# its network.
#
#   IDRAC_HOST=idrac.example.org IDRAC_USERNAME=root IDRAC_PASSWORD=... \
#   IDRAC_SSH_HOST_KEY='ssh-ed25519 AAAA...' \
#     perl -Ilib -It/lib t/idrac/record-racadm.pl idrac8
#
# IDRAC_SSH_KNOWN_HOSTS=/path instead of the key names a known_hosts file;
# with neither, the one of the user is used. IDRAC_SSH_VERIFY=0 accepts any
# host key. IDRAC_SSH_PORT sets the port.
#
# Only reading commands are sent: license view, get, jobqueue view,
# remoteimage -s. Nothing is set, created, deleted or connected.
# The recording is not committed before a person has read it.

use strict;
use warnings;
use File::Path qw( make_path );
use JSON::MaybeXS;
use iDRACSanitizeRacadm;
use WWW::iDRAC::Racadm;

my $name = shift // '';
die "usage: $0 <name>, for example idrac7 or idrac8\n" unless $name =~ /\A[a-z0-9][a-z0-9-]*\z/;
defined $ENV{$_} && length $ENV{$_} or die "set $_\n" for qw( IDRAC_HOST IDRAC_USERNAME IDRAC_PASSWORD );

my ($host) = $ENV{IDRAC_HOST} =~ /\A\[?([^\]]+?)\]?(?::[0-9]+)?\z/;
my $racadm = WWW::iDRAC::Racadm->new(
  host            => $host,
  port            => $ENV{IDRAC_SSH_PORT} || 22,
  username        => $ENV{IDRAC_USERNAME},
  password        => $ENV{IDRAC_PASSWORD},
  verify_host_key => ( $ENV{IDRAC_SSH_VERIFY} // '' ) eq '0' ? 0 : 1,
  ( $ENV{IDRAC_SSH_HOST_KEY}    ? ( host_key    => $ENV{IDRAC_SSH_HOST_KEY} )    : () ),
  ( $ENV{IDRAC_SSH_KNOWN_HOSTS} ? ( known_hosts => $ENV{IDRAC_SSH_KNOWN_HOSTS} ) : () )
);

# the end of the connection on Ctrl+C and on a TERM, as record.pl does for its session
$SIG{INT} = $SIG{TERM} = sub { eval { $racadm->logout }; exit 130 };

# what racadm printed, as it printed it: the errors are part of the recording,
# so the runner is asked directly and nothing is translated
my %raw;
my $send = sub {
  my ( @word ) = @_;
  my $command = WWW::iDRAC::Racadm->command_from(@word);
  my $text    = WWW::iDRAC::Racadm->text_from( $racadm->runner->run( $command, $racadm->timeout ) );
  $raw{$command} = $text;
  return $text;
};

$send->(qw( license view ));
$send->(qw( get BIOS ));
$send->(qw( get BIOS.BiosBootSettings ));
$send->(qw( get BIOS.BiosBootSettings.BootMode ));
$send->(qw( get BIOS.Nonexistent ));
$send->(qw( get iDRAC.VirtualMedia ));
$send->(qw( remoteimage -s ));
my $queue = $send->(qw( jobqueue view ));
my ($id)  = $queue =~ /\[Job ID=((?:JID|RID)_[0-9]+)\]/;
$send->( qw( jobqueue view -i ), $id ) if defined $id;
$send->( qw( jobqueue view -i JID_000000000000 ) );
$racadm->logout;

my $sanitizer = iDRACSanitizeRacadm->new->hide( host => $host )->hide( user => $ENV{IDRAC_USERNAME} )->hide( secret => $ENV{IDRAC_PASSWORD} );
# the host name without its domain is a name of the machine too
$sanitizer->hide( host => $1 ) if $host =~ /\A([^.]+)\./;
my $clean = $sanitizer->sanitize( \%raw );
my @leaks = $sanitizer->leaks($clean);
die "not written, the recording still holds:\n".join( '', map { "  $_\n" } @leaks ) if @leaks;

my $dir = 't/fixtures/'.$name;
make_path($dir);
open my $out, '>:raw', $dir.'/racadm.json' or die "cannot write $dir/racadm.json: $!\n";
print {$out} JSON::MaybeXS->new( utf8 => 1, canonical => 1, pretty => 1 )->encode($clean);
close $out or die "cannot write $dir/racadm.json: $!\n";
printf "%s: %d commands recorded\n", $dir.'/racadm.json', scalar keys %$clean;
