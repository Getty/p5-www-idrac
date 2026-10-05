#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use JSON::MaybeXS;
use iDRACSanitize;

my $JSON    = JSON::MaybeXS->new( utf8 => 1, canonical => 1 );
my $system  = '/redfish/v1/Systems/System.Embedded.1';
my $manager = '/redfish/v1/Managers/iDRAC.Embedded.1';

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
    PowerState    => 'On',
    MemorySummary => { TotalSystemMemoryGiB => 32 },
    Boot          => { BootSourceOverrideEnabled => JSON::MaybeXS::true },
    Actions       => { '#ComputerSystem.Reset' => { target => $system.'/Actions/ComputerSystem.Reset' } }
  },
  $manager => {
    FirmwareVersion => '2.83.83.83',
    DNSRacName      => 'ab',
    Description     => 'Service tag ABC1234 belongs to pichu.lan.example.net, cable ab. Login of root from 10.20.30.99 at 12:30:45, then from fe80::99. Firmware 2.83.83.83.',
    Oem             => { Dell => { ServiceTag => 'ABC1234', Anything => 'at all' } }
  },
  $manager.'/EthernetInterfaces/NIC.1' => {
    FQDN                => 'idrac-ABC1234.lan.example.net',
    MACAddress          => '18:66:da:aa:bb:cc',
    PermanentMACAddress => '18:66:DA:AA:BB:CC',
    IPv4Addresses       => [ { Address => '10.20.30.40', SubnetMask => '255.255.255.0', Gateway => '10.20.30.1' } ],
    IPv6Addresses       => [ { Address => 'fe80::1a66:daff:feaa:bbcc' }, { Address => '::' } ],
    NameServers         => [ '10.20.30.1', '0.0.0.0' ],
    VLAN                => { VLANId => 42 }
  },
  $manager.'/Logs/Sel' => {
    Members => [ { Id => '1', Created => '2026-10-01T12:30:45+02:00', MessageId => 'USR0030', Message => 'Successfully logged in using jdoe, from 10.20.30.99 and GUI.', MessageArgs => [ 'jdoe', '10.20.30.99', 'GUI' ] } ]
  }
);

my $sanitizer = iDRACSanitize->new->hide( host => 'idrac-t330.lan' )->hide( user => 'root' )->hide( secret => 'calvin' );
my $clean     = $sanitizer->sanitize( \%docs );
my $sys       = $clean->{$system};
my $nic       = $clean->{ $manager.'/EthernetInterfaces/NIC.1' };
my $mgr       = $clean->{$manager};
my $entry     = $clean->{ $manager.'/Logs/Sel' }{Members}[0];

subtest 'identifying values by their key' => sub {
  is( $sys->{SKU}, 'TAG0001', 'the service tag' );
  is( $sys->{SerialNumber}, 'SERIAL0001', 'the serial number' );
  is( $sys->{UUID}, '00000000-0000-0000-0000-000000000001', 'the UUID, still in the form of one' );
  like( $sys->{HostName}, qr/\Ahost-\d+\z/, 'a host name' );
  like( $mgr->{DNSRacName}, qr/\Ahost-\d+\z/, 'however short' );
  isnt( $mgr->{DNSRacName}, $sys->{HostName}, 'two names, two placeholders' );
  is( $sys->{AssetTag}, '', 'an empty value stays empty' );
  like( $nic->{FQDN}, qr/\Afqdn-\d+\.example\.org\z/, 'a full name' );
};

subtest 'what is left out altogether' => sub {
  ok( !exists $mgr->{Oem}, 'vendor sections, which hold what nobody has looked at' );
  ok( !exists $entry->{MessageArgs}, 'the arguments of a log message' );
  is( $entry->{Message}, 'Message text removed (USR0030).', 'and its text, which names users and the places they came from' );
  is( $entry->{Created}, '2026-10-01T12:30:45+02:00', 'the rest of the entry stays' );
  is( $entry->{MessageId}, 'USR0030', 'the message id with it' );
  my $old = iDRACSanitize->new->sanitize( { '/l' => { Members => [ { Created => '2026-10-05T04:58:18+02:00', MessageID => 'USR0030', Message => 'Successfully logged in using jdoe.' } ] } } )->{'/l'}{Members}[0];
  is( $old->{Message}, 'Message text removed (USR0030).', 'the id is named where the controller spells its key MessageID' );
};

subtest 'the same values inside other strings' => sub {
  like( $mgr->{Description}, qr/\AService tag TAG0001 belongs to fqdn-\d+\.example\.org, cable ab\. /, 'the tag and a name under a known domain; a value of fewer than four characters is not searched for' );
  like( $mgr->{Description}, qr/Login of user-1 from 192\.0\.2\.\d+ at 12:30:45, then from 2001:db8::[0-9a-f]+\. Firmware /, 'the user, addresses inside a sentence and at the end of one; a time is no IPv6 address' );
  my %lower = ( Text => 'The name was changed to idrac-abc1234, the OS reports PICHU.' );
  my $again = iDRACSanitize->new->sanitize( { %docs, '/x' => \%lower } );
  unlike( $again->{'/x'}{Text}, qr/abc1234|pichu/i, 'whatever case they are written in' );
};

subtest 'addresses' => sub {
  is( $nic->{MACAddress}, $nic->{PermanentMACAddress}, 'the same MAC address in other case, the same placeholder' );
  like( $nic->{MACAddress}, qr/\A00:00:5E:00:53:[0-9A-F]{2}\z/, 'from the documentation range' );
  my $v4 = $nic->{IPv4Addresses}[0];
  like( $v4->{Address}, qr/\A192\.0\.2\.\d+\z/, 'an IPv4 address' );
  is( $v4->{SubnetMask}, '255.255.255.0', 'the netmask kept' );
  is_deeply( $nic->{NameServers}, [ $v4->{Gateway}, '0.0.0.0' ], 'the same address the same placeholder, the unset one kept' );
  like( $nic->{IPv6Addresses}[0]{Address}, qr/\A2001:db8::[0-9a-f]+\z/, 'an IPv6 address' );
  is( $nic->{IPv6Addresses}[1]{Address}, '::', 'the unset one kept' );
  my $odd = iDRACSanitize->new->sanitize( { '/y' => { MACAddress => '1866DAAABBCD', Description => 'WWPN 20:00:18:66:DA:AA:BB:CC' } } )->{'/y'};
  unlike( $JSON->encode($odd), qr/1866DAAABBCD|18:66|AA:BB/i, 'a MAC address without separators, and a longer address of the same kind' );
};

subtest 'what must stay as it is' => sub {
  is( $mgr->{FirmwareVersion}, '2.83.83.83', 'a firmware version under its own key is no IPv4 address' );
  is( $sys->{BiosVersion}, '2.4.3', 'the BIOS version' );
  is( $sys->{Model}, 'PowerEdge T330', 'the model' );
  is( $sys->{PowerState}, 'On', 'states' );
  is( $sys->{'@odata.id'}, $system, 'addresses of documents' );
  is( $sys->{'@odata.type'}, '#ComputerSystem.v1_0_2.ComputerSystem', 'types' );
  is( $sys->{Actions}{'#ComputerSystem.Reset'}{target}, $system.'/Actions/ComputerSystem.Reset', 'action targets' );
  is_deeply( [ sort keys %$clean ], [ sort keys %docs ], 'the paths' );
  is( $docs{$system}{SKU}, 'ABC1234', 'the input is not changed' );
  like( $JSON->encode($sys), qr/"TotalSystemMemoryGiB":32[,}]/, 'a number stays a number' );
  like( $JSON->encode($nic), qr/"VLANId":42[,}]/, 'wherever it is' );
  like( $JSON->encode($sys), qr/"BootSourceOverrideEnabled":true/, 'and a boolean a boolean' );
  my $filler = iDRACSanitize->new->sanitize( { '/z' => { SerialNumber => 'Unknown', AssetTag => 'N/A', Status => { Health => 'Unknown' } } } )->{'/z'};
  is_deeply( $filler, { SerialNumber => 'Unknown', AssetTag => 'N/A', Status => { Health => 'Unknown' } }, 'a filler is no serial number, and is not hunted through the other strings' );
};

subtest 'a recording that was cleaned before' => sub {
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_ };
  my %once = ( '/a' => { SerialNumber => 'SERIAL0002', Note => 'MAC 00:00:5E:00:53:07, UUID 00000000-0000-0000-0000-000000000009, address 192.0.2.7 and 2001:db8::7' }, '/b' => { SerialNumber => 'CN0REALSERIAL' } );
  my $again = iDRACSanitize->new;
  my $out   = $again->sanitize( \%once );
  is( $out->{'/a'}{Note}, $once{'/a'}{Note}, 'placeholders inside a text are left as they are' );
  is_deeply( \@warnings, [], 'without a warning' );
  is_deeply( [ $again->leaks($out) ], [], 'and a value that looks like the placeholder of another is no leak' );

  my $reserved = iDRACSanitize->new;
  my $named    = $reserved->sanitize( { '/c' => { FQDN => 'idrac-7.lab.example.org', Note => 'mail to admin@example.org' } } );
  like( $named->{'/c'}{FQDN}, qr/\Afqdn-\d+\.example\.org\z/, 'a name under example.org is replaced like any other' );
  is_deeply( [ $reserved->leaks($named) ], [], 'and example.org itself, which the placeholders are made of, is no leak' );
};

subtest 'what a real controller showed' => sub {
  # an iDRAC 7 names the hardware address of a network card inside its UEFI
  # device path, and the user root is part of the word PciRoot
  my %real = (
    '/n' => { MACAddress => '9C:69:B4:61:2C:F0', UefiDevicePath => 'PciRoot(0x0)/Pci(0x3,0x0)/Pci(0x0,0x0)/MAC(9C69B4612CF0,0x0)', Note => 'user root logged in; rooted and uprooted stay' },
    '/m' => { UefiDevicePath => 'PciRoot(0x0)/Pci(0x3,0x0)/Pci(0x0,0x1)/MAC(9c69b4612cf1,0x0)' }
  );
  my $s   = iDRACSanitize->new->hide( user => 'root' )->hide( host => 'kaiser' );
  my $out = $s->sanitize( { %real, '/k' => { Note => 'kaiser, Kaiser-idrac and kaiserschmarrn' } } );
  my ( $compact ) = $out->{'/n'}{UefiDevicePath} =~ m{\APciRoot\(0x0\)/Pci\(0x3,0x0\)/Pci\(0x0,0x0\)/MAC\(([0-9A-F]{12}),0x0\)\z};
  ok( $compact, 'the path keeps its form, PciRoot included' ) or diag $out->{'/n'}{UefiDevicePath};
  like( $compact // '', qr/\A00005E0053/, 'and its hardware address is one from the documentation range' );
  ( my $colons = $out->{'/n'}{MACAddress} ) =~ tr/://d;
  is( $compact, $colons, 'the same one the address has where it is written with colons' );
  unlike( $out->{'/m'}{UefiDevicePath}, qr/9c69b4/i, 'in lower case too' );
  is( $out->{'/n'}{Note}, 'user user-1 logged in; rooted and uprooted stay', 'a user name is replaced as a word, not inside other words' );
  is( $out->{'/k'}{Note}, 'host-1, host-1-idrac and kaiserschmarrn', 'and so is a host name' );
  is_deeply( [ $s->leaks($out) ], [], 'nothing is left' );
  is_deeply( [ $s->leaks( { '/x' => { Path => 'PciRoot(0x0)' } } ) ], [], 'and PciRoot is no leak of the user root' );
};

subtest 'the controller reached by its address' => sub {
  my $by_ip = iDRACSanitize->new->hide( host => '10.20.30.40' )->sanitize( { '/n' => { Address => '10.20.30.40', Note => 'reached at 10.20.30.40' } } )->{'/n'};
  like( $by_ip->{Address}, qr/\A192\.0\.2\.\d+\z/, 'stays an address in the recording' );
  is( $by_ip->{Note}, 'reached at '.$by_ip->{Address}, 'the same one everywhere' );
};

subtest 'what a controller keeps in places nobody expects' => sub {
  my %wild = (
    $manager.'/Attributes' => { Attributes => {
      'Users.2.UserName'                    => 'root',
      'Users.3.UserName'                    => 'jdoe',
      'SNMP.1.AgentCommunity'               => 's3cr3t-community',
      'EmailAlert.1.Address'                => 'jane.doe@corp.example',
      'NIC.1.DNSRacName'                    => 'bmc-rack7',
      'NIC.1.DNSDomainName'                 => 'mgmt.corp.example',
      'ActiveDirectory.1.DomainController1' => 'dc01.corp.example',
      'LDAP.1.BindDN'                       => 'cn=svc-idrac,ou=svc,dc=corp,dc=example',
      'SysLog.1.Server1'                    => 'syslog.corp.example',
      'ServerOS.1.HostName'                 => 'db-prod-07',
      'ServerTopology.1.DataCenterName'     => 'FRA-2',
      'ServerTopology.1.RackName'           => 'R17',
      'Security.1.CsrOrganizationName'      => 'Conflict Industries',
      'SNMPAlert.1.Destination'             => '10.20.30.99'
    } },
    $manager.'/Logs/Lclog' => { Members => [
      { Id => '9', Message => 'Successfully logged in using jdoe, from 10.20.30.99 and GUI.', MessageArgs => [ 'jdoe', '10.20.30.99', 'GUI' ], MessageId => 'USR0030' },
      { Id => '8', Message => 'Successfully logged in using admin.smith@corp.example, from 10.20.30.98 and SSH.', Created => '2026-10-01T00:00:00+02:00' }
    ] },
    '/redfish/v1/Chassis/System.Embedded.1' => { Location => { Info => 'DC Frankfurt;Aisle 3;Rack 17', PostalAddress => { City => 'Frankfurt' } }, PartNumber => '0FCJNDA05' },
    $system.'/Storage/Drives/Disk.Bay.0'    => { Identifiers => [ { DurableName => '5000C500A1B2C3D4', DurableNameFormat => 'NAA' } ], SerialNumber => 'ZC1ABCDE' },
    $manager.'/Oem/Dell/DellLicenses/1'     => { EntitlementID => 'FD00000012345678', AssignedDevices => 'ABC1234' },
    $manager.'/VirtualMedia/CD'             => {
      '@odata.id' => 'https://pichu-idrac.hq.conflict.example/redfish/v1/Managers/iDRAC.Embedded.1/VirtualMedia/CD',
      Image       => '//fileserver.corp.example/iso/debian.iso',
      Actions     => { '#VirtualMedia.InsertMedia' => { target => 'https://pichu-idrac.hq.conflict.example/x' } }
    }
  );
  my $wild = iDRACSanitize->new->hide( host => '10.20.30.40' )->hide( user => 'root' );
  my $out  = $wild->sanitize( { %docs, %wild } );
  my $text = $JSON->encode($out);
  for my $needle ( 'jdoe', 's3cr3t-community', 'jane.doe', 'corp.example', 'bmc-rack7', 'svc-idrac', 'db-prod-07', 'FRA-2', 'R17', 'Conflict Industries', 'admin.smith', 'Frankfurt',
    'Rack 17', '5000C500A1B2C3D4', 'FD00000012345678', 'ZC1ABCDE', 'pichu-idrac', 'conflict.example', 'fileserver', '10.20.30', 'ABC1234', 'pichu', 'lan.example.net' ) {
    ok( index( lc $text, lc $needle ) < 0, 'gone: '.$needle );
  }
  is( $out->{ $manager.'/VirtualMedia/CD' }{'@odata.id'}, 'https://idrac.test/redfish/v1/Managers/iDRAC.Embedded.1/VirtualMedia/CD', 'an address given as a full URL keeps its path' );
  is( $out->{'/redfish/v1/Chassis/System.Embedded.1'}{PartNumber}, '0FCJNDA05', 'a part number is no secret' );
  is_deeply( [ $wild->leaks($out) ], [], 'and the check for leaks finds nothing' );
};

subtest 'leaks' => sub {
  is_deeply( [ $sanitizer->leaks($clean) ], [], 'nothing is left in what was cleaned' );
  my @found = $sanitizer->leaks( \%docs );
  ok( scalar( grep { $_ eq 'a tag in '.$system } @found ), 'a value that is still there is found, named by its kind and the document' ) or diag explain \@found;
  ok( scalar( grep { /\Aa (?:serial|uuid|host|fqdn|domain) in / } @found ) >= 4, 'so are the others' ) or diag explain \@found;
  unlike( join( ' ', @found ), qr/ABC1234|CN701636|10\.20\.30|calvin/, 'and the report does not repeat the values' );
  my @secret = $sanitizer->leaks( { '/s' => { Note => 'the password is calvin' } } );
  is_deeply( \@secret, ['a secret in /s'], 'a value hidden by hand is looked for too' );
  is_deeply( [ $sanitizer->leaks( { '/t' => { '@odata.type' => '#ServiceRoot.v1_0_2.ServiceRoot', 'RootCause' => 'x' } } ) ], [], 'a word that merely contains one of the values is no leak' );
  is_deeply( [ iDRACSanitize->new->leaks( iDRACSanitize->new->sanitize( { '/u' => { SKU => 'TAG0001' } } ) ) ], [], 'a value that already is its placeholder is none either' );
};

done_testing;
