#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

# Live test against a real iDRAC. Off unless IDRAC_HOST, IDRAC_USERNAME and
# IDRAC_PASSWORD are set. IDRAC_SSL_FINGERPRINT pins the certificate,
# IDRAC_VERIFY_SSL=0 accepts any.
#
# As it is, the test only reads. With IDRAC_LIVE_DESTRUCTIVE=1, exactly that
# value, it also empties the system event log, switches the server off and on
# again and restarts the controller. That hits a real machine: do not set it
# for one that is in use.
#
# The server is switched off by asking its operating system. Where the
# controller does not offer that, the switching is skipped, unless
# IDRAC_LIVE_FORCE_OFF=1 allows cutting the power instead.
#
# Whatever happens on the way, the test tries to leave the server in the
# power state it found it in. The same rule applies to that restore: a
# graceful shutdown when the controller offers one, the cut only when
# IDRAC_LIVE_FORCE_OFF=1 has allowed it, otherwise a loud diag and no
# power action at all.

BEGIN {
  plan skip_all => 'set IDRAC_HOST, IDRAC_USERNAME and IDRAC_PASSWORD to run the iDRAC live test'
    unless 3 == grep { defined $ENV{$_} && length $ENV{$_} } qw( IDRAC_HOST IDRAC_USERNAME IDRAC_PASSWORD );
}

use Scalar::Util qw( blessed );
use iDRACRestorePower;
use iDRACShapes;
use WWW::iDRAC;

my $idrac = WWW::iDRAC->new(
  host     => $ENV{IDRAC_HOST},
  username => $ENV{IDRAC_USERNAME},
  password => $ENV{IDRAC_PASSWORD},
  ( $ENV{IDRAC_SSL_FINGERPRINT} ? ( ssl_fingerprint => $ENV{IDRAC_SSL_FINGERPRINT} ) : () ),
  # only an explicit 0 turns the check off; an empty or mistyped value does not
  verify_ssl => ( $ENV{IDRAC_VERIFY_SSL} // '' ) eq '0' ? 0 : 1
);
my $cap = $idrac->capabilities;

# the power state the server was found in, from the moment the test starts switching,
# and the same gentle / force decision the switching block made — visible to the
# END block, which runs after the SKIP block has long exited
my $found;
my $gentle;
my $force;

END {
  iDRACRestorePower::restore_power_to( $idrac, $found, $gentle, $force );
  eval { $idrac->logout } if $idrac;
}

sub unsupported { blessed $_[0] && $_[0]->isa('WWW::iDRAC::Error::Unsupported') }

subtest 'the controller' => sub {
  my $facts = $cap->facts;
  diag sprintf 'iDRAC %s, firmware %s, %s, Redfish %s', map { $_ // '?' } @$facts{qw( generation firmware model redfish_version )};
  ok( defined $facts->{redfish_version}, 'speaks Redfish' );
  ok( defined $facts->{firmware}, 'names its firmware' );
  like( $facts->{generation} // '', qr/\A(?:7|8|9|10)\z/, 'and its generation is recognised' );
};

subtest 'reading' => sub {
  for my $method ( read_methods() ) {
    my ( $area, $call ) = split /\./, $method;
    my $got;
    if ( eval { $got = $idrac->$area->$call; 1 } ) {
      shape_ok( $got, $method );
      ok( $cap->supports($method), $method.': supports agrees' );
    }
    else {
      my $error = $@;
      ok( unsupported($error), $method.': not on this controller' );
      diag $error;
      ok( !$cap->supports($method), $method.': supports agrees' );
    }
  }
  like( $idrac->power->state // 'undef', qr/\A[a-z_]+\z/, 'power.state' );
  diag sprintf '%-18s %s', $_.':', $cap->supports($_) ? 'yes' : 'no' for qw( power.on power.off power.restart power.cycle logs.clear_sel manager.restart );
};

subtest 'what the design assumes' => sub {
  my $info = $idrac->system->info;
  ok( defined $info->{service_tag}, 'the service tag is where it is looked for' );
  ok( defined $info->{model}, 'the model' );
  for my $log (qw( sel lifecycle )) {
    my $entries = eval { $idrac->logs->$log( limit => 10 ) } or next;
    my @created = grep { defined } map { $_->{created} } @$entries;
    next unless @created > 1;
    my $all  = eval { $idrac->logs->$log( limit => 200 ) } || [];
    my @full = grep { defined } map { $_->{created} } @$all;
    is( $created[0], $full[0], $log.': the first entries the controller serves are the newest' );
  }
};

subtest 'sessions' => sub {
  is( $idrac->logout, 1, 'logout ends the session' );
  ok( defined $idrac->power->state, 'and the next request opens a new one' );
};

subtest 'changing things' => sub {
  plan skip_all => 'set IDRAC_LIVE_DESTRUCTIVE=1 to empty the event log, switch the server and restart the controller'
    unless ( $ENV{IDRAC_LIVE_DESTRUCTIVE} // '' ) eq '1';

  SKIP: {
    skip 'logs.clear_sel is not on this controller', 3 unless $cap->supports('logs.clear_sel');
    is( $idrac->logs->clear_sel, 1, 'clear_sel' );
    # an iDRAC 7 answers every read of the log with an error while it erases it,
    # for about a minute
    my $sel;
    for ( 1 .. 30 ) {
      last if $sel = eval { $idrac->logs->sel };
      sleep( $ENV{IDRAC_LIVE_PAUSE} // 10 );
    }
    ok( $sel, 'the event log can be read again' ) or diag $@;
    skip 'the event log did not come back', 1 unless $sel;
    cmp_ok( scalar @$sel, '<=', 2, 'the event log is empty, but for what the clearing itself logs' );
  }

  SKIP: {
    my $power = $idrac->power;
    my $start = $power->state // '';
    skip 'the server is neither on nor off but '.$start, 4 unless $start eq 'on' || $start eq 'off';
    skip 'power.on is not on this controller', 4 unless $cap->supports('power.on');
    $gentle = $cap->supports('power.off');
    $force  = ( $ENV{IDRAC_LIVE_FORCE_OFF} // '' ) eq '1';
    skip 'power.off is not on this controller; set IDRAC_LIVE_FORCE_OFF=1 to cut the power instead', 4 unless $gentle || $force;
    diag 'power.off is not on this controller, the power is cut instead' unless $gentle;
    my %step = (
      off => sub { $gentle ? $power->off : $power->off( force => 1 ) },
      on  => sub { $power->on }
    );
    $found = $start;
    for my $want ( $start eq 'on' ? qw( off on ) : qw( on off ) ) {
      is( $step{$want}->(), 1, 'power '.$want );
      my $reached = $power->wait_for( $want, timeout => 600, interval => 10 );
      ok( $reached, 'the server is '.$want );
      next if $reached;
      diag 'the server did not get '.$want.' in ten minutes and may still be on its way: THE TEST STOPS SWITCHING HERE, LOOK AFTER THE SERVER BY HAND';
      undef $found;
      last;
    }
  }

  SKIP: {
    skip 'manager.restart is not on this controller', 2 unless $cap->supports('manager.restart');
    is( $idrac->manager->restart, 1, 'manager restart' );
    my $back;
    for ( 1 .. 60 ) {
      sleep( $ENV{IDRAC_LIVE_PAUSE} // 10 );
      last if $back = eval { $idrac->manager->info };
    }
    ok( $back, 'the controller is back' );
  }
};

done_testing;
