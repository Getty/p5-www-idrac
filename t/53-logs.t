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

subtest 'sel' => sub {
  my $sel = idrac( FakeiDRAC->new )->logs->sel;
  shape_ok( $sel, 'logs.sel' );
  is_deeply( [ map { $_->{id} } @$sel ], [ 3, 2, 1 ], 'newest first' );
  is_deeply( $sel->[1], { id => '2', created => '2026-10-02T08:00:00+02:00', severity => 'critical', message => 'Fan 2 failed.', message_id => 'FAN0001' }, 'translated, the severity in lower case' );
};

subtest 'lifecycle' => sub {
  my $fake = FakeiDRAC->new;
  my $log  = idrac($fake)->logs->lifecycle;
  shape_ok( $log, 'logs.lifecycle' );
  is_deeply( [ map { $_->{id} } @$log ], [ 3, 2, 1 ], 'all pages' );
  is( $log->[2]{severity}, 'informational', 'a severity that is no health level is kept' );
  my $two = idrac($fake)->logs->lifecycle( limit => 2 );
  is_deeply( [ map { $_->{id} } @$two ], [ 3, 2 ], 'limit takes the front of the list' );
  isa_ok( error_of { idrac($fake)->logs->lifecycle( limit => 'all' ) }, 'WWW::iDRAC::Error::Validation', 'a limit that is no number' );
};

subtest 'the default limit' => sub {
  my $fake = FakeiDRAC->new;
  $fake->doc( $manager.'/Logs/Sel' )->{Members} = [ map { { '@odata.id' => $manager.'/Logs/Sel/'.$_, Id => "$_", Created => sprintf( '2026-09-%02dT00:00:%02d+02:00', 1 + int( $_ / 60 ), $_ % 60 ) } } 1 .. 120 ];
  is( scalar @{ idrac($fake)->logs->sel }, 50, '50 entries unless told otherwise' );
  is( scalar @{ idrac($fake)->logs->sel( limit => 120 ) }, 120, 'more on request' );
};

subtest 'entries without a date' => sub {
  my $entry = WWW::iDRAC::Logs->entry_from( {} );
  shape_ok( $entry, 'logs.sel' );
  is_deeply( [ grep { defined $entry->{$_} } keys %$entry ], [], 'every key is there and undef' );
  my $fake = FakeiDRAC->new;
  delete $fake->doc( $manager.'/Logs/Sel' )->{Members}[0]{Created};
  is_deeply( [ map { $_->{id} } @{ idrac($fake)->logs->sel } ], [ 3, 1, 2 ], 'sort last' );
};

subtest 'entries across UTC offsets' => sub {
  # 02:00 in -08:00 (10:00 UTC) is later than 08:00 in +02:00 (06:00 UTC),
  # but string ordering puts the +02:00 entry first when offsets differ
  my $fake = FakeiDRAC->new;
  $fake->doc( $manager.'/Logs/Sel' )->{Members} = [
    { '@odata.id' => $manager.'/Logs/Sel/A', Created => '2026-10-02T08:00:00+02:00', Severity => 'OK',    Message => 'A', MessageId => 'A' },
    { '@odata.id' => $manager.'/Logs/Sel/B', Created => '2026-10-02T02:00:00-08:00', Severity => 'OK',    Message => 'B', MessageId => 'B' },
    { '@odata.id' => $manager.'/Logs/Sel/C', Created => '2026-10-02T12:00:00Z',      Severity => 'OK',    Message => 'C', MessageId => 'C' }
  ];
  is_deeply( [ map { $_->{message_id} } @{ idrac($fake)->logs->sel } ], [ 'C', 'B', 'A' ], 'newest first across offsets, by UTC' );
  is( WWW::iDRAC::Logs::_epoch( '2026-10-02T02:00:00-08:00' ), WWW::iDRAC::Logs::_epoch( '2026-10-02T10:00:00Z' ), 'the same moment, the same epoch' );
};

subtest 'clear_sel' => sub {
  my $fake = FakeiDRAC->new;
  my $logs = idrac($fake)->logs;
  is( $logs->clear_sel, 1, 'returns true' );
  is( $fake->requests->[-1]->method.' '.$fake->requests->[-1]->uri->path, 'POST '.$manager.'/LogServices/Sel/Actions/LogService.ClearLog', 'at the target the log service names' );
  is_deeply( $logs->sel, [], 'the log is empty' );
};

subtest 'a controller without these logs' => sub {
  my $fake = FakeiDRAC->new;
  my $logs = idrac($fake)->logs;
  ok( $logs->supports($_), $_ ) for qw( sel lifecycle clear_sel );
  ok( !eval { $logs->supports('clear_lifecycle'); 1 }, 'there is no clear_lifecycle' );

  delete $fake->doc( $manager.'/LogServices/Sel' )->{Actions};
  my $posts = $fake->seen(qr/\APOST .*ClearLog/);
  my $error = error_of { $logs->clear_sel };
  isa_ok( $error, 'WWW::iDRAC::Error::Unsupported', 'a log service without a clear action' );
  is( $error->capability, 'logs.clear_sel', 'names the capability' );
  is( scalar $fake->seen(qr/\APOST .*ClearLog/), $posts, 'nothing was sent' );

  $fake->doc( $manager.'/LogServices' )->{Members} = [ { '@odata.id' => $manager.'/LogServices/Sel' } ];
  like( error_of { $logs->lifecycle }, qr/\Alogs\.lifecycle is not available on this iDRAC: the controller has no log service lclog\z/, 'no lifecycle log' );
  ok( !$logs->supports('lifecycle'), 'supports says so' );

  delete $fake->doc( $manager.'/LogServices/Sel' )->{Id};
  is( scalar @{ $logs->sel }, 3, 'a service without an Id is found by its address' );

  delete $fake->doc($manager)->{LogServices};
  isa_ok( error_of { $logs->sel }, 'WWW::iDRAC::Error::Unsupported', 'a manager without log services' );
};

subtest 'entries that are linked but not there' => sub {
  my $fake = FakeiDRAC->new;
  $fake->remove( $manager.'/Logs/Sel' );
  my $logs = idrac($fake)->logs;
  isa_ok( error_of { $logs->sel }, 'WWW::iDRAC::Error::Unsupported', 'sel' );
  ok( !$logs->supports('sel'), 'supports says the same' );
  ok( $logs->supports('lifecycle'), 'and still yes for the other log' );
};

subtest 'a member of a collection that is not there' => sub {
  my $fake = FakeiDRAC->new;
  push @{ $fake->doc( $manager.'/Logs/Sel' )->{Members} },
    { '@odata.id' => $manager.'/Logs/Sel/Gone' };
  my $error = error_of { idrac($fake)->logs->sel };
  isa_ok( $error, 'WWW::iDRAC::Error::API', 'a missing member is an API error' );
  like( "$error", qr/Logs\/Sel\/Gone/, 'names the missing member' );
  unlike( "$error", qr{\A\s*GET\s+\S+Sel\s+failed}, 'does not blame just the collection' );
};

subtest 'service_from and clear_action_from without I/O' => sub {
  my $sel   = { Id => 'Sel', '@odata.id' => '/x/Sel' };
  my $lc    = { Id => 'Lclog', '@odata.id' => '/x/Lclog' };
  is( WWW::iDRAC::Logs->service_from( sel => [ $sel, $lc ] ), $sel, 'sel matches Sel' );
  is( WWW::iDRAC::Logs->service_from( lclog => [ $sel, $lc ] ), $lc, 'lclog matches Lclog' );
  is( WWW::iDRAC::Logs->service_from( sel => [ $lc ] ), undef, 'no match' );
  is( WWW::iDRAC::Logs->clear_action_from( { Actions => { '#LogService.ClearLog' => { target => '/x/Sel/Actions/LogService.ClearLog' } } } ),
    '/x/Sel/Actions/LogService.ClearLog', 'the target' );
  my $none = error_of { WWW::iDRAC::Logs->clear_action_from( {} ) };
  isa_ok( $none, 'WWW::iDRAC::Error::Unsupported', 'a log service without a clear action' );
  is( $none->capability, 'logs.clear_sel', 'names the capability' );
};

subtest 'what the real controllers call things' => sub {
  # iDRAC 7 (2.65) and iDRAC 8 (2.50): the services are SEL and LC, at .../LogServices/Sel and .../LogServices/Lclog
  my $fake = FakeiDRAC->new;
  $fake->doc( $manager.'/LogServices/Sel' )->{Id}   = 'SEL';
  $fake->doc( $manager.'/LogServices/Lclog' )->{Id} = 'LC';
  my $logs = idrac($fake)->logs;
  is( scalar @{ $logs->sel }, 3, 'the event log under the name SEL' );
  is( scalar @{ $logs->lifecycle }, 3, 'the lifecycle log under the name LC' );
  ok( $logs->supports('lifecycle'), 'supports agrees' );
  # iDRAC 8 (2.50) spells the key with a capital D
  is( WWW::iDRAC::Logs->entry_from( { MessageID => 'USR0030' } )->{message_id}, 'USR0030', 'the message id under the key MessageID' );
  is( WWW::iDRAC::Logs->entry_from( { MessageId => 'a', MessageID => 'b' } )->{message_id}, 'a', 'the standard spelling first' );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
