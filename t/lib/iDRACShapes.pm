package iDRACShapes;

# The keys every public reading method of WWW::iDRAC returns, in one place
# for the unit tests, the fixture test and the live suite.
#
#   shape_ok( $idrac->system->info, 'system.info' );

use strict;
use warnings;
use Exporter qw( import );
use Test::More;

our @EXPORT = qw( shape_ok read_methods );

our %KEYS = (
  'system.info'            => [qw( manufacturer model service_tag serial uuid asset_tag hostname bios_version power_state health cpu_count cpu_model memory_gib )],
  'system.processors'      => [qw( name model cores threads speed_mhz health )],
  'system.memory'          => [qw( name size_mib type speed_mhz manufacturer part_number serial health )],
  'system.nics'            => [qw( name mac speed_mbps link_up health )],
  'power.consumption'      => [qw( watts average_watts min_watts max_watts capacity_watts )],
  'sensors.temperatures'   => [qw( name celsius upper_warning upper_critical lower_warning lower_critical health )],
  'sensors.fans'           => [qw( name reading units health )],
  'sensors.voltages'       => [qw( name volts health )],
  'sensors.power_supplies' => [qw( name model serial firmware capacity_watts input_volts output_watts health )],
  'logs.sel'               => [qw( id created severity message message_id )],
  'logs.lifecycle'         => [qw( id created severity message message_id )],
  'manager.info'           => [qw( model firmware health date_time uuid )],
  'manager.network'        => [qw( hostname fqdn mac ipv4 ipv6 dns )]
);

sub read_methods { sort keys %KEYS }

sub shape_ok {
  my ( $got, $name ) = @_;
  my $want = join ' ', sort @{ $KEYS{$name} or die 'no shape for '.$name };
  my @rows = ref $got eq 'ARRAY' ? @$got : ($got);
  my @bad  = grep { ref $_ ne 'HASH' || join( ' ', sort keys %$_ ) ne $want } @rows;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  return ok( !@bad, $name.': '.( ref $got eq 'ARRAY' ? scalar(@rows).' entries, each' : 'a hash' ).' with exactly the documented keys' )
    || diag( 'documented: '.$want, map { "\ngot: ".( ref $_ eq 'HASH' ? join ' ', sort keys %$_ : $_ // 'undef' ) } @bad );
}

1;
