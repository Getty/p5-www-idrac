package iDRACRestorePower;

# The decision the END block of t/90-live-idrac.t uses to put the server
# back where the test found it. Pulled out so it can be unit-tested
# against a FakeiDRAC without a live controller.
#
#   iDRACRestorePower::restore_power_to( $idrac, $found, $gentle, $force );
#
# $idrac  the facade; its ->power must answer ->on and ->off, and ->state
# $found  the state the server was in when the test started switching,
#         or undef when nothing was decided
# $gentle true iff the controller offers a graceful shutdown
# $force  true iff IDRAC_LIVE_FORCE_OFF=1 — the maintainer has allowed the
#         test to cut the power
#
# Returns nothing; reports through Test::More::diag. No-op when $idrac is
# missing or $found is unset; no-op when the server is already back where
# it started.

use strict;
use warnings;

sub restore_power_to {
  my ( $idrac, $found, $gentle, $force ) = @_;

  return unless $idrac && $found;

  my $now = eval { $idrac->power->state } // 'unknown';
  return if $now eq $found;

  Test::More::diag( 'the server was '.$found.' when the test began and is '.$now.' now: putting it back' );

  my $action;
  if ( $found eq 'on' ) {
    $action = sub { $idrac->power->on };
  }
  elsif ( $gentle ) {
    $action = sub { $idrac->power->off };
  }
  elsif ( $force ) {
    $action = sub { $idrac->power->off( force => 1 ) };
  }
  else {
    Test::More::diag( 'power.off is not on this controller and IDRAC_LIVE_FORCE_OFF is not set: LOOK AFTER THE SERVER BY HAND' );
    return;
  }

  eval { $action->(); 1 }
    or Test::More::diag( 'THAT FAILED, LOOK AFTER THE SERVER BY HAND: '.$@ );
}

1;