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

my $manager = '/redfish/v1/Managers/iDRAC.Embedded.1';

subtest 'facts' => sub {
  my $fake = FakeiDRAC->new;
  my $cap  = idrac($fake)->capabilities;
  is_deeply( $cap->facts, { generation => 8, model => 'PowerEdge T330', firmware => '2.83.83.83', redfish_version => '1.0.2', license => undef }, 'the five facts' );
  is( $cap->generation, 8, 'generation' );
  is( $cap->model, 'PowerEdge T330', 'model of the server' );
  is( $cap->firmware, '2.83.83.83', 'firmware of the controller' );
  is( $cap->redfish_version, '1.0.2', 'Redfish version' );
  is( $cap->license, undef, 'the license is not read in this version' );
  my $before = @{ $fake->requests };
  $cap->generation for 1 .. 3;
  is( scalar @{ $fake->requests }, $before, 'read once' );
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
