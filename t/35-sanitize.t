#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use iDRACSanitize;

my $system = '/redfish/v1/Systems/System.Embedded.1';

my %docs = (
  $system => {
    '@odata.id'   => $system,
    '@odata.type' => '#ComputerSystem.v1_0_2.ComputerSystem',
    SKU           => 'ABC1234',
    SerialNumber  => 'CN701636AB0013',
    UUID          => '4c4c4544-0042-4310-8031-c2c04f313233',
    AssetTag      => '',
    HostName      => 'pichu',
    BiosVersion   => '2.4.3',
    Model         => 'PowerEdge T330',
    Actions       => { '#ComputerSystem.Reset' => { target => $system.'/Actions/ComputerSystem.Reset' } }
  },
  '/redfish/v1/Managers/iDRAC.Embedded.1' => {
    FirmwareVersion => '2.83.83.83',
    Oem             => { Dell => { ServiceTag => 'ABC1234', DNSRacName => 'ab', Note => 'Service tag ABC1234 belongs to pichu.lan.example.net', Slot => 'cable ab' } }
  },
  '/redfish/v1/Managers/iDRAC.Embedded.1/EthernetInterfaces/NIC.1' => {
    FQDN                => 'idrac-ABC1234.lan.example.net',
    MACAddress          => '18:66:da:aa:bb:cc',
    PermanentMACAddress => '18:66:DA:AA:BB:CC',
    IPv4Addresses       => [ { Address => '10.20.30.40', SubnetMask => '255.255.255.0', Gateway => '10.20.30.1' } ],
    IPv6Addresses       => [ { Address => 'fe80::1a66:daff:feaa:bbcc' }, { Address => '::' } ],
    NameServers         => [ '10.20.30.1', '0.0.0.0' ]
  },
  '/redfish/v1/Managers/iDRAC.Embedded.1/Logs/Sel' => {
    Members => [ { Id => '1', Created => '2026-10-01T12:30:45+02:00', Message => 'Login of root from 10.20.30.99 at 12:30:45, then from fe80::99. Firmware 2.83.83.83.' } ]
  }
);

my $sanitizer = iDRACSanitize->new->hide( host => 'idrac-t330.lan' )->hide( user => 'root' );
my $clean     = $sanitizer->sanitize( \%docs );
my $sys       = $clean->{$system};
my $nic       = $clean->{'/redfish/v1/Managers/iDRAC.Embedded.1/EthernetInterfaces/NIC.1'};
my $manager   = $clean->{'/redfish/v1/Managers/iDRAC.Embedded.1'};
my $entry     = $clean->{'/redfish/v1/Managers/iDRAC.Embedded.1/Logs/Sel'}{Members}[0];

subtest 'identifying values by their key' => sub {
  is( $sys->{SKU}, 'TAG0001', 'the service tag' );
  is( $sys->{SerialNumber}, 'SERIAL0001', 'the serial number' );
  is( $sys->{UUID}, '00000000-0000-0000-0000-000000000001', 'the UUID, still in the form of one' );
  is( $sys->{HostName}, 'host-3', 'a host name' );
  is( $manager->{Oem}{Dell}{DNSRacName}, 'host-2', 'however short' );
  is( $sys->{AssetTag}, '', 'an empty value stays empty' );
  is( $manager->{Oem}{Dell}{ServiceTag}, 'TAG0001', 'the same value gets the same placeholder everywhere' );
};

subtest 'the same values inside other strings' => sub {
  is( $manager->{Oem}{Dell}{Note}, 'Service tag TAG0001 belongs to host-3.example-1.org', 'the tag, the name and the domain inside a sentence' );
  is( $manager->{Oem}{Dell}{Slot}, 'cable ab', 'a value of fewer than four characters is not searched for inside other strings' );
  is( $nic->{FQDN}, 'fqdn-1.example.org', 'a value that is replaced as a whole' );
};

subtest 'addresses' => sub {
  is( $nic->{MACAddress}, '00:00:5E:00:53:01', 'a MAC address' );
  is( $nic->{PermanentMACAddress}, '00:00:5E:00:53:01', 'the same one in other case' );
  is_deeply( $nic->{IPv4Addresses}, [ { Address => '192.0.2.1', SubnetMask => '255.255.255.0', Gateway => '192.0.2.2' } ], 'IPv4 addresses, the netmask kept' );
  is_deeply( $nic->{IPv6Addresses}, [ { Address => '2001:db8::1' }, { Address => '::' } ], 'an IPv6 address, the unset one kept' );
  is_deeply( $nic->{NameServers}, [ '192.0.2.2', '0.0.0.0' ], 'the same address the same placeholder, the unset one kept' );
  is( $entry->{Message}, 'Login of user-1 from 192.0.2.3 at 12:30:45, then from 2001:db8::2. Firmware 192.0.2.4.', 'inside a sentence and at the end of one, the user name with it; a time is no IPv6 address' );
  is( $entry->{Created}, '2026-10-01T12:30:45+02:00', 'a timestamp is left alone' );
};

subtest 'what must stay as it is' => sub {
  is( $manager->{FirmwareVersion}, '2.83.83.83', 'a firmware version under its own key is no IPv4 address' );
  is( $sys->{BiosVersion}, '2.4.3', 'the BIOS version' );
  is( $sys->{Model}, 'PowerEdge T330', 'the model' );
  is( $sys->{'@odata.id'}, $system, 'addresses of documents' );
  is( $sys->{'@odata.type'}, '#ComputerSystem.v1_0_2.ComputerSystem', 'types' );
  is( $sys->{Actions}{'#ComputerSystem.Reset'}{target}, $system.'/Actions/ComputerSystem.Reset', 'action targets' );
  is_deeply( [ sort keys %$clean ], [ sort keys %docs ], 'the paths' );
  is( $docs{$system}{SKU}, 'ABC1234', 'the input is not changed' );
};

subtest 'leaks' => sub {
  my @secret = ( 'ABC1234', 'CN701636AB0013', '10.20.30.40', '18:66:da:aa:bb:cc', 'fe80::1a66:daff:feaa:bbcc', 'lan.example.net', 'pichu', 'idrac-t330.lan' );
  is_deeply( [ iDRACSanitize->leaks( $clean, @secret ) ], [], 'none of the identifying values is left' );
  is_deeply( [ iDRACSanitize->leaks( \%docs, @secret, undef, '' ) ], [ sort @secret[ 0 .. 6 ] ], 'and leaks finds them where they are' );
};

done_testing;
