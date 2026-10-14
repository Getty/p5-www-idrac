#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use FakeRacadm;
use iDRACShapes;
use WWW::iDRAC;

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

# racadm is switched off unless a test brings a fake one: nothing here may reach for SSH
sub idrac { WWW::iDRAC->new( host => $_[0]->host, username => 'root', password => 'calvin', ua => $_[0], ssh => 0, @_[ 1 .. $#_ ] ) }

my $manager = '/redfish/v1/Managers/iDRAC.Embedded.1';

subtest 'facts' => sub {
  my $fake = FakeiDRAC->new;
  my $cap  = idrac($fake)->capabilities;
  is_deeply( $cap->facts, { generation => 8, model => 'PowerEdge T330', firmware => '2.83.83.83', redfish_version => '1.0.2', license => undef }, 'the five facts' );
  is( $cap->generation, 8, 'generation' );
  is( $cap->model, 'PowerEdge T330', 'model of the server' );
  is( $cap->firmware, '2.83.83.83', 'firmware of the controller' );
  is( $cap->redfish_version, '1.0.2', 'Redfish version' );
  is( $cap->license, undef, 'no license without racadm' );
  my $before = @{ $fake->requests };
  $cap->generation for 1 .. 3;
  is( scalar @{ $fake->requests }, $before, 'read once' );
};

subtest 'the license is read over racadm' => sub {
  my %want = ( 'iDRAC8 Express License' => 'express', 'iDRAC7 Enterprise License' => 'enterprise', 'iDRAC9 Datacenter License' => 'datacenter', 'iDRAC7 Basic Management' => 'basic' );
  for my $description ( sort keys %want ) {
    my $racadm = FakeRacadm->new( license => $description );
    my $cap    = idrac( FakeiDRAC->new, ssh => 1, racadm => $racadm->transport )->capabilities;
    is( $cap->license, $want{$description}, $description );
  }
  my $racadm = FakeRacadm->new;
  my $fake   = FakeiDRAC->new;
  my $cap    = idrac( $fake, ssh => 1, racadm => $racadm->transport )->capabilities;
  is( $cap->generation, 8, 'the generation is Redfish alone' );
  is_deeply( $racadm->commands, [], 'and opens no SSH connection' );
  is( $cap->facts->{license}, 'enterprise', 'facts has the license' );
  is_deeply( $racadm->commands, ['racadm license view'], 'read with one command' );
  $cap->license for 1 .. 3;
  is( scalar @{ $racadm->commands }, 1, 'read once' );

  is( WWW::iDRAC::Capabilities->license_from("License Description  = iDRAC7 Express License\nLicense Description  = iDRAC7 Enterprise License\n"), 'enterprise', 'the highest of several' );
  is( WWW::iDRAC::Capabilities->license_from("Status = OK\n"), undef, 'undef when none is listed' );
  is( WWW::iDRAC::Capabilities->license_from(undef), undef, 'and for nothing' );

  for my $case ( [ 'refused' => FakeRacadm->new( fail => WWW::iDRAC::Error::Network->new( message => 'refused', cause => 'refused' ) ) ],
                 [ 'an error of racadm' => FakeRacadm->new( replies => { 'racadm license view' => "ERROR: RAC1019: no\n" } ) ] ) {
    my ( $name, $broken ) = @$case;
    is( idrac( FakeiDRAC->new, ssh => 1, racadm => $broken->transport )->capabilities->license, undef, 'undef when the license cannot be read: '.$name );
  }
  my $switched_off = FakeRacadm->new;
  is( idrac( FakeiDRAC->new, racadm => $switched_off->transport( enabled => 0 ) )->capabilities->license, undef, 'undef with ssh => 0' );
  is_deeply( $switched_off->commands, [], 'and nothing sent' );
  my $bad = FakeRacadm->new( fail => 'a bug in the runner' );
  ok( !eval { idrac( FakeiDRAC->new, ssh => 1, racadm => $bad->transport )->capabilities->license; 1 }, 'what is not one of our errors is not swallowed' );
};

subtest 'generation' => sub {
  my %want = ( '12G Monolithic' => 7, '12G Modular' => 7, '13G Monolithic' => 8, '14G Monolithic' => 9, '15G Monolithic' => 9, '16G Monolithic' => 9, '17G Monolithic' => 10 );
  is( WWW::iDRAC::Capabilities->generation_from($_), $want{$_}, $_ ) for sort keys %want;
  is( WWW::iDRAC::Capabilities->generation_from($_), undef, 'undef for '.( $_ // 'undef' ) ) for undef, '', 'iDRAC', '11G Monolithic', 'G13', [];
};

subtest 'a controller that says little' => sub {
  my $fake = FakeiDRAC->new;
  delete $fake->doc('/redfish/v1')->{Managers};
  delete $fake->doc('/redfish/v1/Systems/System.Embedded.1')->{Links};
  delete $fake->doc('/redfish/v1/Systems/System.Embedded.1')->{Model};
  is_deeply( idrac($fake)->capabilities->facts, { generation => undef, model => undef, firmware => undef, redfish_version => '1.0.2', license => undef }, 'undef for what it does not say' );
};

subtest 'supports' => sub {
  my $fake = FakeiDRAC->new;
  my $cap  = idrac($fake)->capabilities;
  ok( $cap->supports($_), $_ ) for qw( system.info system.nics power.on power.off power.consumption sensors.temperatures logs.sel logs.clear_sel manager.info manager.restart );
  ok( !$cap->supports($_), 'not '.$_ ) for qw( power.cycle system.memory );
  push @{ $fake->doc('/redfish/v1/Systems/System.Embedded.1')->{Actions}{'#ComputerSystem.Reset'}{'ResetType@Redfish.AllowableValues'} }, 'PowerCycle';
  ok( $cap->supports('power.cycle'), 'asked anew each time' );
  for my $name ( 'power', 'power.', 'storage.volumes', 'power.explode', 'Power.on', '', undef, [] ) {
    isa_ok( error_of { $cap->supports($name) }, 'WWW::iDRAC::Error::Validation', 'unknown: '.( defined $name ? ref $name ? 'a reference' : "'$name'" : 'undef' ) );
  }
};

subtest 'supports for what is served over racadm' => sub {
  my $racadm = FakeRacadm->new;
  my $cap    = idrac( FakeiDRAC->new, ssh => 1, racadm => $racadm->transport )->capabilities;
  ok( $cap->supports($_), $_ ) for qw( bios.groups bios.group bios.get bios.set bios.commit jobs.list jobs.get jobs.delete jobs.wait virtual_media.status virtual_media.connect virtual_media.disconnect );
  my $unlicensed = FakeRacadm->new( licensed => 0, lists_groups => 0 );
  my $cap2       = idrac( FakeiDRAC->new, ssh => 1, racadm => $unlicensed->transport )->capabilities;
  ok( $cap2->supports($_), $_ ) for qw( bios.get bios.set jobs.list virtual_media.status );
  ok( !$cap2->supports($_), 'not '.$_ ) for qw( bios.groups virtual_media.connect virtual_media.disconnect );
  my $off = idrac( FakeiDRAC->new )->capabilities;
  ok( !$off->supports($_), 'ssh => 0: not '.$_ ) for qw( bios.get bios.set jobs.list virtual_media.status virtual_media.connect );
  isa_ok( error_of { $cap->supports('bios.explode') }, 'WWW::iDRAC::Error::Validation', 'unknown method of a racadm area' );
  isa_ok( error_of { $cap->supports('virtual_media.') }, 'WWW::iDRAC::Error::Validation', 'and an empty one' );
};

subtest 'the capabilities outlive the facade' => sub {
  my $fake = FakeiDRAC->new;
  my $cap  = idrac($fake)->capabilities;
  is( $cap->generation, 8, 'facts' );
  ok( $cap->supports('power.on'), 'supports' );
  undef $cap;
  is( $fake->sessions, 0, 'and the session ends with them' );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
