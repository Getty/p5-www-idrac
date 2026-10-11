#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use iDRACShapes;
use WWW::iDRAC;

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

sub idrac { WWW::iDRAC->new( host => $_[0]->host, username => 'root', password => 'calvin', ua => $_[0] ) }

my $system = '/redfish/v1/Systems/System.Embedded.1';
my $reset  = $system.'/Actions/ComputerSystem.Reset';

subtest 'state' => sub {
  my $fake  = FakeiDRAC->new;
  my $power = idrac($fake)->power;
  is( $power->state, 'on', 'on' );
  $fake->doc($system)->{PowerState} = 'Off';
  is( $power->state, 'off', 'read anew each time' );
  $fake->doc($system)->{PowerState} = 'PoweringOn';
  is( $power->state, 'powering_on', 'a state in between, in the same form' );
  delete $fake->doc($system)->{PowerState};
  is( $power->state, undef, 'undef when the controller does not say' );
};

subtest 'switching' => sub {
  my $fake  = FakeiDRAC->new;
  my $power = idrac($fake)->power;
  my $sent  = sub { $fake->requests->[-1]->method.' '.$fake->requests->[-1]->uri->path.' '.$fake->requests->[-1]->content };
  is( $power->off, 1, 'off returns true' );
  is( $sent->(), 'POST '.$reset.' {"ResetType":"GracefulShutdown"}', 'and asks for a graceful shutdown at the target the system names' );
  is( $power->state, 'off', 'the server is off' );
  $power->on;
  is( $sent->(), 'POST '.$reset.' {"ResetType":"On"}', 'on' );
  $power->off( force => 1 );
  is( $sent->(), 'POST '.$reset.' {"ResetType":"ForceOff"}', 'off with force' );
  $power->restart;
  is( $sent->(), 'POST '.$reset.' {"ResetType":"GracefulRestart"}', 'restart' );
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_ };
  for my $call ( [ 'on',      $power->can('on')      ], [ 'off',     $power->can('off') ], [ 'restart', $power->can('restart') ], [ 'cycle',   $power->can('cycle') ] ) {
    my ( $name, $cv ) = @$call;
    my $positional = error_of { $cv->( $power, 1 ) };
    isa_ok( $positional, 'WWW::iDRAC::Error::Validation', "$name(1) is a validation error, not a warning" );
    my $unknown = error_of { $cv->( $power, bogus => 1 ) };
    isa_ok( $unknown, 'WWW::iDRAC::Error::Validation', "$name(bogus => 1) names the unknown argument" )
      if $name eq 'off' || $name eq 'restart';
  }
  is_deeply( \@warnings, [], 'no warnings from positional or unknown arguments' );
};

subtest 'an order this controller does not offer' => sub {
  my $fake  = FakeiDRAC->new;
  my $power = idrac($fake)->power;
  $power->state;
  my $posts = $fake->seen(qr/\APOST .*Reset/);
  for my $case ( [ cycle => 'PowerCycle', sub { $power->cycle } ], [ restart => 'ForceRestart', sub { $power->restart( force => 1 ) } ] ) {
    my ( $method, $type, $code ) = @$case;
    my $error = error_of { $code->() };
    isa_ok( $error, 'WWW::iDRAC::Error::Unsupported', $method );
    is( $error->capability, 'power.'.$method, 'names the capability' );
    like( $error->reason, qr/\Areset type $type is not offered, only On, ForceOff, /, 'and what is offered instead' );
  }
  is( scalar $fake->seen(qr/\APOST .*Reset/), $posts, 'nothing was sent' );

  push @{ $fake->doc($system)->{Actions}{'#ComputerSystem.Reset'}{'ResetType@Redfish.AllowableValues'} }, 'PowerCycle';
  is( $power->cycle, 1, 'cycle where it is offered' );
  is( $fake->requests->[-1]->content, '{"ResetType":"PowerCycle"}', 'asks for a power cycle' );

  delete $fake->doc($system)->{Actions}{'#ComputerSystem.Reset'}{'ResetType@Redfish.AllowableValues'};
  is( $power->restart( force => 1 ), 1, 'without a list of allowed values the order is sent' );

  delete $fake->doc($system)->{Actions};
  like( error_of { $power->on }, qr/\Apower\.on is not available on this iDRAC: the system offers no reset action\z/, 'a system without a reset action' );
};

subtest 'wait_for' => sub {
  my $fake  = FakeiDRAC->new( delay => 3 );
  my $power = idrac($fake)->power;
  $power->off;
  is( $power->state, 'on', 'the server takes its time' );
  is( $power->wait_for( 'off', timeout => 30, interval => 0 ), 1, 'true when the state is reached' );
  is( $power->state, 'off', 'which it then is' );
  is( $power->wait_for( 'on', timeout => 0, interval => 0 ), 0, 'false when the time is up' );
  is( $power->wait_for('off'), 1, 'a state already reached returns at once' );
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_ };
  isa_ok( error_of { $power->wait_for('standby') }, 'WWW::iDRAC::Error::Validation', 'a state that is neither on nor off' );
  isa_ok( error_of { $power->wait_for }, 'WWW::iDRAC::Error::Validation', 'no state' );
  my $with_undef = error_of { $power->wait_for(undef) };
  isa_ok( $with_undef, 'WWW::iDRAC::Error::Validation', 'undef state' );
  is( "$with_undef", 'wait_for waits for on or off', 'the message says what wait_for waits for, without echoing the bad state' );
  my $with_junk = error_of { $power->wait_for('standby') };
  unlike( "$with_junk", qr/standby/, 'a bad state is not echoed in the message' );
  isa_ok( error_of { $power->wait_for( 'off', timeout => 'soon' ) }, 'WWW::iDRAC::Error::Validation', 'a non-numeric timeout' );
  isa_ok( error_of { $power->wait_for( 'off', timeout => -1 ) }, 'WWW::iDRAC::Error::Validation', 'a negative timeout' );
  isa_ok( error_of { $power->wait_for( 'off', interval => 'soon' ) }, 'WWW::iDRAC::Error::Validation', 'a non-numeric interval' );
  isa_ok( error_of { $power->wait_for( 'off', interval => -1 ) }, 'WWW::iDRAC::Error::Validation', 'a negative interval' );
  is( $power->wait_for( 'off', timeout => 30, interval => 5 ), 1, 'valid positive numbers work' );
  is( $power->wait_for( 'off', timeout => 0 ), 1, 'timeout 0 and the default interval' );
  is_deeply( \@warnings, [], 'no warnings' );
};

subtest 'consumption' => sub {
  my $fake = FakeiDRAC->new;
  my $now  = idrac($fake)->power->consumption;
  shape_ok( $now, 'power.consumption' );
  is_deeply( $now, { watts => 87, average_watts => 84, min_watts => 61, max_watts => 143, capacity_watts => 495 }, 'translated' );
  shape_ok( WWW::iDRAC::Power->consumption_from($_), 'power.consumption' ) for {}, { PowerControl => [] }, { PowerControl => [ { PowerMetrics => 'n/a' } ] }, undef;
  delete $fake->doc('/redfish/v1/Chassis/System.Embedded.1')->{Power};
  my $error = error_of { idrac($fake)->power->consumption };
  isa_ok( $error, 'WWW::iDRAC::Error::Unsupported', 'a chassis without a power resource' );
  is( $error->capability, 'power.consumption', 'names the capability' );
};

subtest 'supports' => sub {
  my $power = idrac( FakeiDRAC->new )->power;
  ok( $power->supports($_), $_ ) for qw( state wait_for on off restart consumption );
  ok( !$power->supports('cycle'), 'cycle is not offered' );
  isa_ok( error_of { $power->supports('reset_action') }, 'WWW::iDRAC::Error::Validation', 'a helper is no capability' );
};

subtest 'a power resource that is linked but not there' => sub {
  my $fake = FakeiDRAC->new;
  $fake->remove('/redfish/v1/Chassis/System.Embedded.1/Power');
  my $power = idrac($fake)->power;
  isa_ok( error_of { $power->consumption }, 'WWW::iDRAC::Error::Unsupported', 'consumption' );
  ok( !$power->supports('consumption'), 'supports says the same' );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
