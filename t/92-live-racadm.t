#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

# Live test of the part of WWW::iDRAC that is served over racadm (SSH):
# the license, BIOS attributes, the job queue, virtual media. Off unless
# IDRAC_HOST, IDRAC_USERNAME and IDRAC_PASSWORD are set, as for
# t/90-live-idrac.t. The host key is checked, so one of these is needed:
#
#   IDRAC_SSH_HOST_KEY='ssh-ed25519 AAAA...'   pins the key (ssh-keyscan prints it)
#   IDRAC_SSH_KNOWN_HOSTS=/path/known_hosts    or a file
#   IDRAC_SSH_VERIFY=0                         or accepts any key
#
# With none of them the known_hosts of the user is used. IDRAC_SSH_PORT sets
# a port other than 22, IDRAC_SSH_USERNAME and IDRAC_SSH_PASSWORD another
# login than the one for Redfish.
#
# As it is, the test only reads: it sends license view, get, jobqueue view
# and remoteimage -s. With IDRAC_LIVE_DESTRUCTIVE=1, exactly that value, it
# also writes:
#
#   - sets one BIOS attribute to the value it has now, makes a job of it
#     without a restart, and deletes that job again;
#   - when IDRAC_LIVE_VMEDIA_LOCATION is set (with IDRAC_LIVE_VMEDIA_USERNAME
#     and IDRAC_LIVE_VMEDIA_PASSWORD for a share), attaches that image and
#     detaches it again.
#
# That hits a real machine's controller: do not set it for one that is in use.
# It never restarts the server.

BEGIN {
  plan skip_all => 'set IDRAC_HOST, IDRAC_USERNAME and IDRAC_PASSWORD to run the iDRAC live test'
    unless 3 == grep { defined $ENV{$_} && length $ENV{$_} } qw( IDRAC_HOST IDRAC_USERNAME IDRAC_PASSWORD );
}

use Scalar::Util qw( blessed );
use iDRACShapes;
use WWW::iDRAC;

my $idrac = WWW::iDRAC->new(
  host     => $ENV{IDRAC_HOST},
  username => $ENV{IDRAC_USERNAME},
  password => $ENV{IDRAC_PASSWORD},
  ( $ENV{IDRAC_SSL_FINGERPRINT} ? ( ssl_fingerprint => $ENV{IDRAC_SSL_FINGERPRINT} ) : () ),
  verify_ssl => ( $ENV{IDRAC_VERIFY_SSL} // '' ) eq '0' ? 0 : 1,
  ssh_port   => $ENV{IDRAC_SSH_PORT} || 22,
  ssh_verify_host_key => ( $ENV{IDRAC_SSH_VERIFY} // '' ) eq '0' ? 0 : 1,
  ( $ENV{IDRAC_SSH_HOST_KEY}    ? ( ssh_host_key    => $ENV{IDRAC_SSH_HOST_KEY} )    : () ),
  ( $ENV{IDRAC_SSH_KNOWN_HOSTS} ? ( ssh_known_hosts => $ENV{IDRAC_SSH_KNOWN_HOSTS} ) : () ),
  ( $ENV{IDRAC_SSH_USERNAME} && $ENV{IDRAC_SSH_PASSWORD} ? ( ssh_username => $ENV{IDRAC_SSH_USERNAME}, ssh_password => $ENV{IDRAC_SSH_PASSWORD} ) : () )
);
my $cap = $idrac->capabilities;

END { eval { $idrac->logout } if $idrac }

sub unsupported { blessed $_[0] && $_[0]->isa('WWW::iDRAC::Error::Unsupported') }

subtest 'the license' => sub {
  my $license = $cap->license;
  diag 'license: '.( $license // 'not readable' );
  ok( !defined $license || $license =~ /\A(?:basic|express|enterprise|datacenter)\z/, 'one of the four, or undef' );
  ok( defined $license, 'readable over racadm' );
};

subtest 'reading' => sub {
  for my $call ( racadm_methods() ) {
    my ( $method, @arg ) = @$call;
    my ( $area, $name ) = split /\./, $method;
    my $got;
    if ( eval { $got = $idrac->$area->$name(@arg); 1 } ) {
      if    ( $method eq 'bios.groups' ) { ok( !grep( { ref $_ } @$got ), $method.': a list of names' ) }
      elsif ( $method eq 'bios.get' )    { ok( !ref $got, $method.': a plain value' ) }
      else                               { shape_ok( $got, $method ) }
      ok( $cap->supports($method), $method.': supports agrees' );
      diag sprintf '%s: %s', $method, join ', ', map { $_ // 'undef' } ref $got eq 'ARRAY' ? scalar(@$got).' entries' : ref $got eq 'HASH' ? map { "$_=".( $got->{$_} // 'undef' ) } sort keys %$got : $got;
    }
    else {
      my $error = $@;
      ok( unsupported($error), $method.': not on this controller' ) or diag $error;
      diag $error;
      ok( !$cap->supports($method), $method.': supports agrees' );
    }
  }
  if ( $cap->supports('jobs.get') && ( my $first = $idrac->jobs->list->[0] ) ) {
    is_deeply( $idrac->jobs->get( $first->{id} ), $first, 'jobs.get: the same job as the list shows' );
  }
  my $e = eval { $idrac->bios->get('BiosBootSettings.NoSuchAttributeHere'); undef } // $@;
  SKIP: {
    skip 'bios.get is not on this controller', 1 unless $cap->supports('bios.get');
    ok( blessed $e && $e->isa('WWW::iDRAC::Error::API') && $e->is_not_found, 'an attribute that is not there is a not found' ) or diag $e;
  }
  diag sprintf '%-26s %s', $_.':', $cap->supports($_) ? 'yes' : 'no' for qw( bios.set bios.commit jobs.delete jobs.wait virtual_media.connect virtual_media.disconnect );
};

subtest 'the connection' => sub {
  is( $idrac->racadm->connected, 1, 'one SSH connection was kept for all of it' );
  ok( $idrac->logout, 'logout ends it' );
  ok( !$idrac->racadm->connected, 'and it is closed' );
  ok( defined $cap->supports('jobs.list'), 'the next command connects again' );
};

subtest 'changing things' => sub {
  plan skip_all => 'set IDRAC_LIVE_DESTRUCTIVE=1 to stage a BIOS value, make and delete a job, and attach an image'
    unless ( $ENV{IDRAC_LIVE_DESTRUCTIVE} // '' ) eq '1';

  SKIP: {
    skip 'bios.set is not on this controller', 6 unless $cap->supports('bios.set');
    skip 'jobs.delete is not on this controller', 6 unless $cap->supports('jobs.delete');
    my ($attribute) = grep { !$_->{read_only} && defined $_->{value} } @{ $idrac->bios->group('BiosBootSettings') };
    skip 'no attribute with a value to set to itself', 6 unless $attribute;
    my $name   = 'BiosBootSettings.'.$attribute->{name};
    my $staged = $idrac->bios->set( $name => $attribute->{value} );
    is( $staged->{value}, $attribute->{value}, 'staged the value it has' );
    ok( $staged->{pending}, 'and the controller says it is pending' );
    my $job = $idrac->bios->commit( reboot => 'none' );
    like( $job->{job_id} // '', qr/\AJID_[0-9]+\z/, 'a job was made' );
    is( $job->{reboot_job_id}, undef, 'and no restart' );
    my $seen = eval { $idrac->jobs->get( $job->{job_id} ) };
    ok( $seen, 'it is in the queue' ) or diag $@;
    is( $idrac->jobs->delete( $job->{job_id} ), 1, 'and is deleted again' );
  }

  SKIP: {
    my $location = $ENV{IDRAC_LIVE_VMEDIA_LOCATION};
    skip 'set IDRAC_LIVE_VMEDIA_LOCATION to attach an image', 3 unless defined $location && length $location;
    skip 'virtual_media.connect is not on this controller', 3 unless $cap->supports('virtual_media.connect');
    my $status = $idrac->virtual_media->connect(
      location => $location,
      ( $ENV{IDRAC_LIVE_VMEDIA_USERNAME} ? ( username => $ENV{IDRAC_LIVE_VMEDIA_USERNAME}, password => $ENV{IDRAC_LIVE_VMEDIA_PASSWORD} // '' ) : () )
    );
    is( $status->{connected}, 1, 'attached' );
    $status = $idrac->virtual_media->disconnect;
    is( $status->{connected}, 0, 'detached' );
    is( $status->{share}, undef, 'and no share is left' );
  }
};

done_testing;
