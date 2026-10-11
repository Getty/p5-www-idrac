#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

# Unit test for the END-block helper t/90-live-idrac.t uses to put a real
# server back into the power state it found it in. Pure-decision helper:
# reads $idrac->power->state (in eval, so a network error becomes 'unknown'),
# decides which power call — if any — would put it back, and reports through
# Test::More::diag.

use iDRACRestorePower;

# Run the helper with $idrac / $found / $gentle / $force, and return both the
# calls the mocked power object saw and the diag the helper emitted. Test::More's
# diag does not write to a filehandle Test::Builder->output() can intercept
# from outside a Context; the reliable way to read it is a per-call local
# override of Test::More::diag.
sub run {
  my ( $idrac, $found, $gentle, $force ) = @_;

  no warnings 'redefine';
  my @diag;
  local *Test::More::diag = sub (;@) {
    push @diag, join '', grep { defined } @_;
    return 0;
  };

  iDRACRestorePower::restore_power_to( $idrac, $found, $gentle, $force );

  return (
    $idrac ? $idrac->power->{calls} : [],
    \@diag,
  );
}

# the calls the helper made on the mocked $power, kept under their action's name
sub by_action {
  my $calls = shift;
  my $got = { on => [], off => [] };
  for my $entry ( @$calls ) {
    push @{ $got->{ $entry->[0] } }, $entry;
  }
  return $got;
}

subtest 'found off, gentle supported, no force — gentle off, on not called' => sub {
  my $power = MockPower->new( state => 'on' );
  my $idrac = MockIdrac->new( $power );
  my ( $calls, $diag ) = run( $idrac, 'off', 1, 0 );
  my $by = by_action( $calls );

  is( scalar @{ $by->{on} },  0, 'on was not called' );
  is( scalar @{ $by->{off} }, 1, 'off was called once' );
  is_deeply( $by->{off}[0][1], {}, 'off was called without args (no force)' );
};

subtest 'gentle unsupported and no force — no call, LOOK AFTER THE SERVER BY HAND' => sub {
  my $power = MockPower->new( state => 'on' );
  my $idrac = MockIdrac->new( $power );
  my ( $calls, $diag ) = run( $idrac, 'off', 0, 0 );

  is_deeply( $calls, [], 'no call was made' );
  ok( scalar @$diag >= 1, 'a diag was emitted' );
  like( join( "\n", @$diag ), qr/LOOK AFTER THE SERVER BY HAND/, '...and it tells the operator to look after the server by hand' );
};

subtest 'gentle unsupported and force set — off( force => 1 )' => sub {
  my $power = MockPower->new( state => 'on' );
  my $idrac = MockIdrac->new( $power );
  my ( $calls, $diag ) = run( $idrac, 'off', 0, 1 );
  my $by = by_action( $calls );

  is( scalar @{ $by->{on} },  0, 'on was not called' );
  is( scalar @{ $by->{off} }, 1, 'off was called once' );
  is_deeply( $by->{off}[0][1], { force => 1 }, 'off was called with force => 1' );
};

subtest 'found on, ends up off — on was called, off was not' => sub {
  my $power = MockPower->new( state => 'off' );
  my $idrac = MockIdrac->new( $power );
  my ( $calls, $diag ) = run( $idrac, 'on', 1, 0 );
  my $by = by_action( $calls );

  is( scalar @{ $by->{on} },  1, 'on was called once' );
  is( scalar @{ $by->{off} }, 0, 'off was not called — switching a server on has no destructive form' );
};

subtest 'no $found — no-op whatever power reports' => sub {
  for my $state ( qw( on off unknown ) ) {
    my $power = MockPower->new( state => $state );
    my $idrac = MockIdrac->new( $power );
    my ( $calls, $diag ) = run( $idrac, undef, 1, 1 );
    is_deeply( $calls, [], "no call was made when power reports '$state'" );
    is_deeply( $diag,  [], "...and nothing was logged when power reports '$state'" );
  }
};

done_testing;

package MockPower;

sub new {
  my ( $class, %arg ) = @_;
  return bless {
    state => $arg{state} // 'on',
    calls => [],
  }, $class;
}

sub state { $_[0]->{state} }

sub on {
  push @{ $_[0]->{calls} }, [ 'on' ];
  return 1;
}

sub off {
  my ( $self, %arg ) = @_;
  push @{ $self->{calls} }, [ 'off', \%arg ];
  return 1;
}

package MockIdrac;

sub new   { bless { power => $_[1] }, $_[0] }
sub power { $_[0]->{power} }
