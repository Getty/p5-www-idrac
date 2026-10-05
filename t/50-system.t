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

my $path = '/redfish/v1/Systems/System.Embedded.1';

subtest 'info' => sub {
  my $info = idrac( FakeiDRAC->new )->system->info;
  shape_ok( $info, 'system.info' );
  is_deeply( $info, {
    manufacturer => 'Dell Inc.',
    model        => 'PowerEdge T330',
    service_tag  => 'TAG0001',
    serial       => 'SERIAL0001',
    uuid         => '00000000-0000-0000-0000-000000000001',
    asset_tag    => undef,
    hostname     => 'server.example.org',
    bios_version => '2.4.3',
    power_state  => 'on',
    health       => 'ok',
    cpu_count    => 1,
    cpu_model    => 'Intel(R) Xeon(R) CPU E3-1230 v5 @ 3.40GHz',
    memory_gib   => 32
  }, 'translated; an empty asset tag is undef' );
};

subtest 'a system document with nothing in it' => sub {
  my $info = WWW::iDRAC::System->info_from( {} );
  shape_ok( $info, 'system.info' );
  is_deeply( [ grep { defined $info->{$_} } keys %$info ], [], 'every key is there and undef' );
  shape_ok( WWW::iDRAC::System->info_from( { ProcessorSummary => 'n/a', MemorySummary => [], Status => 'OK' } ), 'system.info' );
};

subtest 'processors' => sub {
  my $cpus = idrac( FakeiDRAC->new )->system->processors;
  shape_ok( $cpus, 'system.processors' );
  is_deeply( $cpus, [ { name => 'CPU.Socket.1', model => 'Intel(R) Xeon(R) CPU E3-1230 v5 @ 3.40GHz', cores => 4, threads => 8, speed_mhz => 4000, health => 'ok' } ], 'one processor' );
};

subtest 'nics' => sub {
  my $nics = idrac( FakeiDRAC->new )->system->nics;
  shape_ok( $nics, 'system.nics' );
  is_deeply( $nics, [
    { name => 'NIC.Embedded.1-1-1', mac => '00:00:5E:00:53:01', speed_mbps => 1000, link_up => 1, health => 'ok' },
    { name => 'NIC.Embedded.2-1-1', mac => '00:00:5E:00:53:02', speed_mbps => undef, link_up => 0, health => undef }
  ], 'link state as 1 and 0, the permanent address where there is no other, a missing speed as undef' );
  is( WWW::iDRAC::System->nic_from( {} )->{link_up}, undef, 'an unknown link state is undef, not down' );
};

subtest 'memory' => sub {
  my $fake    = FakeiDRAC->new;
  my $missing = error_of { idrac($fake)->system->memory };
  isa_ok( $missing, 'WWW::iDRAC::Error::Unsupported', 'a controller without a memory collection' );
  is( $missing->capability, 'system.memory', 'names the capability' );
  like( "$missing", qr/\Asystem\.memory is not available on this iDRAC: the controller has no Memory resource\z/, 'and says why' );

  $fake->doc($path)->{Memory} = { '@odata.id' => $path.'/Memory' };
  $fake->{docs}{ $path.'/Memory' } = { Members => [ {
    '@odata.id' => $path.'/Memory/DIMM.Socket.A1', DeviceLocator => 'DIMM A1', CapacityMiB => 16384, MemoryDeviceType => 'DDR4',
    OperatingSpeedMhz => 2133, Manufacturer => 'Micron Technology', PartNumber => '18ASF2G72AZ-2G1A1 ', SerialNumber => 'SERIAL0003', Status => { Health => 'OK' }
  } ] };
  my $memory = idrac($fake)->system->memory;
  shape_ok( $memory, 'system.memory' );
  is_deeply( $memory, [ { name => 'DIMM A1', size_mib => 16384, type => 'DDR4', speed_mhz => 2133, manufacturer => 'Micron Technology', part_number => '18ASF2G72AZ-2G1A1', serial => 'SERIAL0003', health => 'ok' } ], 'one module, the part number without its padding' );

  $fake->doc($path)->{Memory} = { '@odata.id' => $path.'/Gone' };
  isa_ok( error_of { idrac($fake)->system->memory }, 'WWW::iDRAC::Error::Unsupported', 'a link that leads to a 404' );
};

subtest 'supports' => sub {
  my $fake   = FakeiDRAC->new;
  my $system = idrac($fake)->system;
  ok( $system->supports($_), $_ ) for qw( info processors nics );
  ok( !$system->supports('memory'), 'memory is not there' );
  isa_ok( error_of { $system->supports('reboot') }, 'WWW::iDRAC::Error::Validation', 'a name that is no method' );
  isa_ok( error_of { $system->supports(undef) }, 'WWW::iDRAC::Error::Validation', 'no name' );

  my $none = FakeiDRAC->new;
  delete $none->doc('/redfish/v1')->{Systems};
  my $error = error_of { idrac($none)->system->info };
  isa_ok( $error, 'WWW::iDRAC::Error::Unsupported', 'a controller without a system' );
  ok( !idrac($none)->system->supports('info'), 'supports says so' );

  my $down = idrac( FakeiDRAC->new( docs => {} ) )->system;
  isa_ok( error_of { $down->supports('info') }, 'WWW::iDRAC::Error::API', 'an error on the way is not a no' );
};

subtest 'a collection that is linked but not there' => sub {
  my $fake = FakeiDRAC->new;
  $fake->remove( $path.'/Processors' );
  my $system = idrac($fake)->system;
  my $error  = error_of { $system->processors };
  isa_ok( $error, 'WWW::iDRAC::Error::Unsupported', 'processors' );
  ok( !$system->supports('processors'), 'supports says the same' );
  ok( $system->supports('nics'), 'and still yes for what is there' );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
