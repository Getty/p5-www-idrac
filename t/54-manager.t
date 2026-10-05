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
my $system  = '/redfish/v1/Systems/System.Embedded.1';

subtest 'info' => sub {
  my $info = idrac( FakeiDRAC->new )->manager->info;
  shape_ok( $info, 'manager.info' );
  is_deeply( $info, { model => '13G Monolithic', firmware => '2.83.83.83', health => 'ok', date_time => '2026-10-04T12:00:00+02:00', uuid => '00000000-0000-0000-0000-000000000002' }, 'translated' );
  shape_ok( WWW::iDRAC::Manager->info_from( {} ), 'manager.info' );
};

subtest 'network' => sub {
  my $network = idrac( FakeiDRAC->new )->manager->network;
  shape_ok( $network, 'manager.network' );
  is_deeply( $network, {
    hostname => 'idrac-TAG0001',
    fqdn     => 'idrac-TAG0001.example.org',
    mac      => '00:00:5E:00:53:10',
    ipv4     => ['192.0.2.10'],
    ipv6     => ['2001:db8::10'],
    dns      => ['192.0.2.53']
  }, 'addresses as lists, the ones that are not set left out' );
  my $empty = WWW::iDRAC::Manager->network_from( { IPv4Addresses => 'none', NameServers => { a => 1 } } );
  shape_ok( $empty, 'manager.network' );
  is_deeply( [ @$empty{qw( ipv4 ipv6 dns )} ], [ [], [], [] ], 'the lists are lists even when the controller sends none' );
};

subtest 'restart' => sub {
  my $fake  = FakeiDRAC->new;
  my $idrac = idrac($fake);
  $idrac->manager->info;
  is( $idrac->manager->restart, 1, 'returns true' );
  is( $fake->requests->[-1]->method.' '.$fake->requests->[-1]->uri->path.' '.$fake->requests->[-1]->content, 'POST '.$manager.'/Actions/Manager.Reset {"ResetType":"GracefulRestart"}', 'a graceful restart at the target the manager names' );
  is( $fake->doc($system)->{PowerState}, 'On', 'the server keeps running' );
  my $before = @{ $fake->requests };
  $idrac->manager->info;
  is_deeply( [ map { $_->method } @{ $fake->requests }[ $before .. $#{ $fake->requests } ] ], [ 'POST', 'GET' ], 'the next request logs in first, instead of sending the token the restart made void' );
  is( scalar $fake->seen(qr/\ADELETE/), 0, 'and nothing tries to end the session the restart ended' );
};

subtest 'a controller that offers less' => sub {
  my $fake    = FakeiDRAC->new;
  my $manager_part = idrac($fake)->manager;
  ok( $manager_part->supports($_), $_ ) for qw( info network restart );

  $fake->doc($manager)->{Actions}{'#Manager.Reset'}{'ResetType@Redfish.AllowableValues'} = ['ForceRestart'];
  my $posts = $fake->seen(qr/\APOST .*Manager\.Reset/);
  my $error = error_of { $manager_part->restart };
  isa_ok( $error, 'WWW::iDRAC::Error::Unsupported', 'a reset type that is not offered' );
  is( $error->capability, 'manager.restart', 'names the capability' );
  is( scalar $fake->seen(qr/\APOST .*Manager\.Reset/), $posts, 'nothing was sent' );

  $fake->doc( $manager.'/EthernetInterfaces' )->{Members} = [];
  like( error_of { $manager_part->network }, qr/\Amanager\.network is not available on this iDRAC: the controller lists no network interface\z/, 'no network interface' );
  delete $fake->doc($manager)->{EthernetInterfaces};
  ok( !$manager_part->supports('network'), 'supports: no interfaces at all' );
};

subtest 'what is linked but not there' => sub {
  my $fake = FakeiDRAC->new;
  $fake->remove( $manager.'/EthernetInterfaces' );
  my $part = idrac($fake)->manager;
  isa_ok( error_of { $part->network }, 'WWW::iDRAC::Error::Unsupported', 'network, the collection is gone' );
  ok( !$part->supports('network'), 'supports says the same' );

  my $empty = FakeiDRAC->new;
  $empty->doc( $manager.'/EthernetInterfaces' )->{Members} = [];
  ok( !idrac($empty)->manager->supports('network'), 'supports: a collection without an interface' );

  my $lost = FakeiDRAC->new;
  delete $lost->doc($system)->{Links};
  $lost->remove('/redfish/v1/Managers');
  my $error = error_of { idrac($lost)->manager->info };
  isa_ok( $error, 'WWW::iDRAC::Error::Unsupported', 'info, the collection of managers is gone' );
  is( $error->capability, 'manager.info', 'names the capability' );
  ok( !idrac($lost)->manager->supports('info'), 'supports says the same' );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
