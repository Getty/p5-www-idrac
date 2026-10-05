#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use iDRACRecorder;
use WWW::iDRAC::Redfish;

my $manager = '/redfish/v1/Managers/iDRAC.Embedded.1';

sub recorder {
  my ( $fake, %arg ) = @_;
  my $redfish = WWW::iDRAC::Redfish->new( base_url => 'https://'.$fake->host, username => 'root', password => 'calvin', ua => $fake );
  return iDRACRecorder->new( redfish => $redfish, %arg );
}

subtest 'the whole tree, with GET only' => sub {
  my $fake = FakeiDRAC->new;
  my $docs = recorder($fake)->record;
  is_deeply( [ sort keys %$docs ], [ sort keys %{ FakeiDRAC->default_docs } ], 'every document the controller has, under the path the fake serves it at' );
  is_deeply( [ $fake->seen(qr/\A(?!GET )/) ], [ 'POST /redfish/v1/Sessions', 'DELETE /redfish/v1/Sessions/1' ], 'nothing but GET, apart from the login and the logout' );
  is( $docs->{$manager}{FirmwareVersion}, '2.83.83.83', 'the documents as they came' );
};

subtest 'a recording can be served again' => sub {
  my $docs  = recorder( FakeiDRAC->new )->record;
  my $again = recorder( FakeiDRAC->new( docs => $docs ) )->record;
  is_deeply( $again, $docs, 'the same recording from the recording' );
};

subtest 'what is not walked' => sub {
  my $fake = FakeiDRAC->new;
  $fake->doc('/redfish/v1')->{AccountService} = { '@odata.id' => '/redfish/v1/Managers/iDRAC.Embedded.1/AccountService' };
  $fake->doc('/redfish/v1')->{JsonSchemas}    = { '@odata.id' => '/redfish/v1/JSONSchemas' };
  $fake->doc($manager)->{Links}               = { Gone => { '@odata.id' => $manager.'/Gone#/Part' }, Elsewhere => { '@odata.id' => 'https://other.test/x' } };
  my $recorder = recorder($fake);
  my $docs     = $recorder->record;
  is_deeply( [ sort @{ $recorder->skipped } ], [ '/redfish/v1/JSONSchemas', '/redfish/v1/Managers/iDRAC.Embedded.1/AccountService', '/redfish/v1/Sessions' ], 'accounts, sessions and schemas are left out' );
  is( scalar $fake->seen(qr/AccountService|JSONSchemas/), 0, 'and not even asked for' );
  is_deeply( [ keys %{ $recorder->failed } ], [ $manager.'/Gone' ], 'a link that leads nowhere is noted, without its fragment, and the walk goes on' );
  ok( exists $docs->{ $manager.'/Logs/Lclog/1' }, 'to the end' );
};

subtest 'only the kinds of document the tests read are kept' => sub {
  my $fake = FakeiDRAC->new;
  $fake->doc($manager)->{Links} = { Attributes => { '@odata.id' => $manager.'/Attributes' } };
  $fake->{docs}{ $manager.'/Attributes' } = {
    '@odata.type' => '#DellAttributes.v1_0_0.DellAttributes',
    Attributes    => { 'Users.3.UserName' => 'jdoe', 'SNMP.1.AgentCommunity' => 's3cr3t' },
    Links         => { More => { '@odata.id' => $manager.'/Attributes/More' } }
  };
  $fake->{docs}{ $manager.'/Attributes/More' } = { Note => 'a document that does not say what it is' };
  my $recorder = recorder($fake);
  my $docs     = $recorder->record;
  ok( !exists $docs->{ $manager.'/Attributes' }, 'a kind of document nobody has looked at is not kept' );
  ok( !exists $docs->{ $manager.'/Attributes/More' }, 'nor one that does not say what it is' );
  is_deeply( [ sort keys %$docs ], [ sort keys %{ FakeiDRAC->default_docs } ], 'everything else is' );
  is( $recorder->walked->{ $manager.'/Attributes' }, 'DellAttributes', 'but it was walked, and its kind noted' );
  is( $recorder->walked->{ $manager.'/Attributes/More' }, '(no type)', 'and what it points to as well' );
  is( $recorder->walked->{'/redfish/v1'}, 'ServiceRoot', 'a type in the old notation is read too' );
  is_deeply( [ $recorder->left_out ], [ $manager.'/Attributes', $manager.'/Attributes/More' ], 'what was left out is listed' );
};

subtest 'limits' => sub {
  my $fake = FakeiDRAC->new;
  $fake->doc( $manager.'/Logs/Sel' )->{Members} = [ map { { '@odata.id' => $manager.'/Logs/Sel/'.$_, Id => "$_" } } 1 .. 30 ];
  my $docs = recorder( $fake, max_members => 5 )->record;
  my $sel  = $docs->{ $manager.'/Logs/Sel' };
  is( scalar @{ $sel->{Members} }, 5, 'a long collection is cut' );
  is( $sel->{'Members@odata.count'}, 5, 'and its count says so' );
  my $log = recorder( FakeiDRAC->new, max_members => 1 )->record->{ $manager.'/Logs/Lclog' };
  ok( !exists $log->{'Members@odata.nextLink'}, 'a cut collection has no next page' );
  my $short = recorder( FakeiDRAC->new, max_docs => 4 );
  is( scalar keys %{ $short->record }, 4, 'the number of documents is capped' );
  cmp_ok( $short->truncated, '>', 0, 'and the recorder says that it stopped with addresses still to walk' );
  my $whole = recorder( FakeiDRAC->new );
  $whole->record;
  is( $whole->truncated, 0, 'which it does not say after a whole walk' );
};

done_testing;
