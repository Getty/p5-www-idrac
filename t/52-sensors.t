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

my $chassis = '/redfish/v1/Chassis/System.Embedded.1';

subtest 'temperatures' => sub {
  my $t = idrac( FakeiDRAC->new )->sensors->temperatures;
  shape_ok( $t, 'sensors.temperatures' );
  is_deeply( $t, [
    { name => 'System Board Inlet Temp', celsius => 23, upper_warning => 42, upper_critical => 47, lower_warning => 3, lower_critical => -7, health => 'ok' },
    { name => 'CPU2 Temp', celsius => undef, upper_warning => undef, upper_critical => undef, lower_warning => undef, lower_critical => undef, health => undef }
  ], 'a sensor without a reading is listed, with undef' );
};

subtest 'fans' => sub {
  my $fans = idrac( FakeiDRAC->new )->sensors->fans;
  shape_ok( $fans, 'sensors.fans' );
  is_deeply( $fans, [
    { name => 'System Board Fan1', reading => 4800, units => 'RPM', health => 'ok' },
    { name => 'System Board Fan2', reading => 0, units => 'RPM', health => 'critical' }
  ], 'the name from either field, a reading of zero kept' );
};

subtest 'voltages' => sub {
  my $v = idrac( FakeiDRAC->new )->sensors->voltages;
  shape_ok( $v, 'sensors.voltages' );
  is_deeply( $v, [ { name => 'PS1 Voltage 1', volts => 230, health => 'ok' }, { name => 'System Board 3.3V PG', volts => undef, health => 'ok' } ], 'translated' );
};

subtest 'power supplies' => sub {
  my $fake = FakeiDRAC->new;
  my $ps   = idrac($fake)->sensors->power_supplies;
  shape_ok( $ps, 'sensors.power_supplies' );
  is_deeply( $ps, [ { name => 'PS1 Status', model => 'PWR SPLY,495W,RDNT,DELTA', serial => 'SERIAL0002', firmware => '00.1D.7D', capacity_watts => 495, input_volts => 230, output_watts => 87, health => 'warning' } ], 'translated, the model without its padding' );
  is( WWW::iDRAC::Sensors->power_supply_from( { PowerOutputWatts => 90 } )->{output_watts}, 90, 'the output under its newer name' );
};

subtest 'documents that are not what they should be' => sub {
  my $fake = FakeiDRAC->new;
  %{ $fake->doc( $chassis.'/Thermal' ) } = ( Temperatures => 'none', Fans => undef );
  is_deeply( idrac($fake)->sensors->temperatures, [], 'no list of temperatures is an empty list' );
  is_deeply( idrac($fake)->sensors->fans, [], 'no list of fans' );
  shape_ok( WWW::iDRAC::Sensors->temperature_from( { ReadingCelsius => 'N/A', Status => 'OK' } ), 'sensors.temperatures' );
};

subtest 'a chassis without sensors' => sub {
  my $fake = FakeiDRAC->new;
  delete $fake->doc($chassis)->{Thermal};
  $fake->remove( $chassis.'/Power' );
  my $sensors = idrac($fake)->sensors;
  for my $method (qw( temperatures fans voltages power_supplies )) {
    my $error = error_of { $sensors->$method };
    isa_ok( $error, 'WWW::iDRAC::Error::Unsupported', $method );
    is( $error->capability, 'sensors.'.$method, 'names the capability' );
  }
  ok( !$sensors->supports('temperatures'), 'supports: no thermal resource' );
  ok( $sensors->supports('voltages'), 'supports follows the link, not the document behind it' );
  ok( idrac( FakeiDRAC->new )->sensors->supports($_), $_ ) for qw( temperatures fans voltages power_supplies );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
