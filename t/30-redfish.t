#!/usr/bin/env perl
use strict;
use warnings;
use POSIX qw( _exit );
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use WWW::iDRAC::Redfish;

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

sub transport {
  my ( $fake, %arg ) = @_;
  return WWW::iDRAC::Redfish->new( base_url => 'https://'.$fake->host, username => 'root', password => 'calvin', ua => $fake, %arg );
}

my $system  = '/redfish/v1/Systems/System.Embedded.1';
my $manager = '/redfish/v1/Managers/iDRAC.Embedded.1';

subtest 'the first request logs in' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  is( $fake->sessions, 0, 'nothing happens before the first request' );
  is( $redfish->get($system)->{Model}, 'PowerEdge T330', 'get returns the document' );
  is_deeply( [ $fake->seen(qr/./) ], [ 'GET /redfish/v1/', 'POST /redfish/v1/Sessions', 'GET '.$system ], 'service root, login, request' );
  is( $fake->requests->[0]->header('Authorization'), undef, 'the service root is read without credentials' );
  $redfish->get($system);
  is( scalar $fake->seen(qr/\APOST/), 1, 'one login for many requests' );
  is( $fake->sessions, 1, 'one session' );
};

subtest 'logout' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  is( $redfish->logout, 0, 'nothing to end before a login' );
  $redfish->get($system);
  is( $redfish->logout, 1, 'ends the session' );
  is( $fake->sessions, 0, 'the controller has none left' );
  is_deeply( [ $fake->seen(qr/\ADELETE/) ], ['DELETE /redfish/v1/Sessions/1'], 'at the address the login was answered with' );
  $redfish->get($system);
  is( $fake->sessions, 1, 'the next request logs in again' );
};

subtest 'a session is ended when the object goes away' => sub {
  my $fake = FakeiDRAC->new;
  {
    my $redfish = transport($fake);
    $redfish->get($system);
    is( $fake->sessions, 1, 'open inside the scope' );
  }
  is( $fake->sessions, 0, 'ended at the end of the scope' );

  my $gone = FakeiDRAC->new;
  {
    my $redfish = transport($gone);
    $redfish->get($system);
    $gone->forget_tokens;
    local $@ = 'untouched';
    undef $redfish;
    is( $@, 'untouched', 'a logout the controller refuses does not die and leaves $@ alone' );
  }
};

subtest 'logout uses a short timeout' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  $fake->timeout(100);
  $redfish->get($system);
  is( $fake->timeouts->[-1], 100, 'a normal request uses the UA timeout' );
  $redfish->logout;
  is( $fake->timeouts->[-1], 5, 'the logout uses a short timeout' );
  is( $redfish->ua->timeout, 100, 'and restores it' );
};

subtest 'a forked child does not end the parent session' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  $redfish->get($system);
  is( $fake->sessions, 1, 'a session is open' );
  my $pid = fork // die 'cannot fork: '.$!;
  if ( $pid == 0 ) {
    eval { $redfish->logout };
    is( $fake->sessions, 1, 'in the child, the parent session is still open' );
    POSIX::_exit(0);
  }
  waitpid $pid, 0;
  is( $fake->sessions, 1, 'and in the parent too' );
  $redfish->logout;
  is( $fake->sessions, 0, 'the parent ends it itself' );
};

subtest 'the process that made the object ends its session' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  $redfish->get($system);
  {
    # as in a child forked after the module was loaded, which makes its own transport
    no warnings 'once';
    local $WWW::iDRAC::Redfish::PID = $$ + 1;
    is( $redfish->logout, 1, 'an object made in this process ends its session, wherever the module was loaded' );
  }
  is( $fake->sessions, 0, 'gone' );
  $redfish->get($system);
  $redfish->{_pid} = $$ + 1;    # as in a child forked after the object was made
  is( $redfish->logout, 0, 'one made in another process does not' );
  is( $fake->sessions, 1, 'and the session stays' );
  $redfish->{_pid} = $$;
  is( $redfish->logout, 1, 'until its own process ends it' );
};

subtest 'a login without a path to the session' => sub {
  my $fake    = FakeiDRAC->new( bare_session => 1 );
  my $redfish = transport($fake);
  my $error   = error_of { $redfish->get($system) };
  isa_ok( $error, 'WWW::iDRAC::Error::API', 'a controller without Location or @odata.id' );
  is( $error->http_status, 201, 'with the status the controller answered' );
  like( "$error", qr/cannot be ended/, 'and why' );
  is( $fake->sessions, 1, 'the session is on the controller' );
  is( scalar $fake->seen(qr/\ADELETE/), 0, 'and no logout was attempted' );
};

subtest 'a refused token is renewed once' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  $redfish->get($system);
  $fake->forget_tokens;
  is( $redfish->get($system)->{Model}, 'PowerEdge T330', 'the request succeeds after a restart of the controller' );
  is( scalar $fake->seen(qr/\APOST/), 2, 'with exactly one more login' );
};

subtest 'wrong credentials' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport( $fake, password => 'wrong-pw' );
  my $error   = error_of { $redfish->get($system) };
  isa_ok( $error, 'WWW::iDRAC::Error::API' );
  ok( $error->is_unauthorized, 'refused as unauthorized' );
  is( $error->message_id, 'IDRAC.1.6.SYS415', 'with the message id of the controller' );
  unlike( "$error", qr/wrong-pw/, 'the message does not contain the password' );
  is( scalar $fake->seen(qr/\APOST/), 1, 'one attempt, no loop' );
};

subtest 'without a session' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport( $fake, session => 0 );
  is( $redfish->get($system)->{Model}, 'PowerEdge T330', 'Basic credentials are accepted' );
  is( scalar $fake->seen(qr/\APOST/), 0, 'no login' );
  is( $redfish->logout, 0, 'and nothing to end' );
  my $error = error_of { transport( $fake, session => 0, password => 'wrong-pw' )->get($system) };
  ok( $error->is_unauthorized, 'wrong credentials are a plain 401' );
};

subtest 'the four verbs' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  is( $redfish->post( $system.'/Actions/ComputerSystem.Reset', { ResetType => 'ForceOff' } ), undef, 'post returns the document, here none' );
  is( $fake->doc($system)->{PowerState}, 'Off', 'the body arrived' );
  is( $fake->requests->[-1]->content, '{"ResetType":"ForceOff"}', 'as JSON' );
  my $refused = error_of { $redfish->post( $system.'/Actions/ComputerSystem.Reset', { ResetType => 'PowerCycle' } ) };
  is( $refused->http_status, 400, 'an error status is an API error' );
  like( $refused->api_message, qr/not supported: PowerCycle/, 'with what the controller said' );
  my $missing = error_of { $redfish->get('/redfish/v1/Nope') };
  ok( $missing->is_not_found, 'a missing path is 404 and stays an API error on this level' );
  my $patch = error_of { $redfish->patch( $system, { AssetTag => 'x' } ) };
  is( $patch->http_status, 405, 'patch sends PATCH' );
  is( $fake->requests->[-1]->content, '{"AssetTag":"x"}', 'with its body' );
  $redfish->get($system);
  is( $redfish->delete('/redfish/v1/Sessions/1'), undef, 'delete sends DELETE' );
  isa_ok( error_of { $redfish->get('redfish/v1') }, 'WWW::iDRAC::Error::Validation', 'a path without a leading slash' );
  isa_ok( error_of { $redfish->get(undef) }, 'WWW::iDRAC::Error::Validation', 'no path' );
};

subtest 'members' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  my @inline  = $redfish->members( $manager.'/Logs/Sel' );
  is_deeply( [ map { $_->{Id} } @inline ], [ 2, 3, 1 ], 'whole entries are taken as they are, in the order of the controller' );
  is( scalar $fake->seen(qr{Logs/Sel/}), 0, 'without a request per entry' );

  my @paged = $redfish->members( $manager.'/Logs/Lclog' );
  is_deeply( [ map { $_->{Id} } @paged ], [ 3, 2, 1 ], 'addresses are fetched, and the second page followed' );

  my $before  = @{ $fake->requests };
  my @limited = $redfish->members( $manager.'/Logs/Lclog', limit => 2 );
  is( scalar @limited, 2, 'limit caps the entries' );
  is( @{ $fake->requests } - $before, 3, 'and the requests: the collection and two entries' );

  $fake->doc( $manager.'/Logs/Lclog?$skip=2' )->{'Members@odata.nextLink'} = 'https://idrac.test'.$manager.'/Logs/Lclog';
  is( scalar( () = $redfish->members( $manager.'/Logs/Lclog' ) ), 3, 'a next link that leads back ends the walk' );

  $fake->doc( $manager.'/Logs/Sel' )->{Members} = undef;
  is_deeply( [ $redfish->members( $manager.'/Logs/Sel' ) ], [], 'a collection without members' );
  isa_ok( error_of { $redfish->members( $manager.'/Logs/Sel', limit => 0 ) }, 'WWW::iDRAC::Error::Validation', 'limit 0' );
};

subtest 'locate' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  is( $redfish->locate('Systems'), $system, 'the system, from the collection' );
  is( $redfish->locate('Chassis'), '/redfish/v1/Chassis/System.Embedded.1', 'the chassis the system names, not the first of the collection' );
  is( $redfish->locate('Managers'), $manager, 'the manager the system names' );
  my $before = @{ $fake->requests };
  $redfish->locate($_) for qw( Systems Chassis Managers );
  is( scalar @{ $fake->requests }, $before, 'remembered' );
  isa_ok( error_of { $redfish->locate('Sessions') }, 'WWW::iDRAC::Error::Validation', 'another kind' );

  my $bare = FakeiDRAC->new;
  delete $bare->doc($system)->{Links};
  delete $bare->doc('/redfish/v1')->{Managers};
  my $other = transport($bare);
  is( $other->locate('Chassis'), '/redfish/v1/Chassis/Enclosure.Internal.0-1', 'without links the first of the collection' );
  is( $other->locate('Managers'), undef, 'undef where the controller has none' );
};

subtest 'a logout the controller refuses' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  $redfish->get($system);
  $fake->forget_tokens;
  my $ended;
  is( error_of { $ended = $redfish->logout }, undef, 'does not die when the controller no longer knows the session' );
  is( $ended, 1, 'and counts as a session that is over' );

  my $moved = FakeiDRAC->new;
  my $other = transport($moved);
  $other->get($system);
  $_ = 99 for values %{ $moved->{tokens} };
  is( error_of { $other->logout }, undef, 'nor when the controller has no session at that address' );
  like( ( $moved->seen(qr/\ADELETE/) )[-1], qr{\ADELETE /redfish/v1/Sessions/1\z}, 'which it was asked for' );
};

subtest 'a resource that refuses the login it is given' => sub {
  my $fake = FakeiDRAC->new;
  $fake->deny($manager);
  my $redfish = transport($fake);
  for ( 1 .. 5 ) {
    my $error = error_of { $redfish->get($manager) };
    ok( $error && $error->is_unauthorized, 'refused, request '.$_ );
  }
  cmp_ok( $fake->sessions, '<=', 1, 'the sessions do not pile up on the controller' );
  is( $redfish->get($system)->{Model}, 'PowerEdge T330', 'and other resources stay reachable' );
  undef $redfish;
  is( $fake->sessions, 0, 'none is left behind' );
};

subtest 'a miss is not remembered' => sub {
  my $fake    = FakeiDRAC->new;
  my $members = $fake->doc('/redfish/v1/Managers')->{Members};
  delete $fake->doc($system)->{Links};
  $fake->doc('/redfish/v1/Managers')->{Members} = [];
  my $redfish = transport($fake);
  is( $redfish->locate('Managers'), undef, 'nothing there' );
  $fake->doc('/redfish/v1/Managers')->{Members} = $members;
  is( $redfish->locate('Managers'), $manager, 'found once it is' );
};

subtest 'an address with characters that are escaped on the way' => sub {
  my $fake = FakeiDRAC->new;
  my $path = '/redfish/v1/Chassis/System.Embedded.1/Sensors/0x17||Fan.Embedded.1A';
  $fake->{docs}{$path} = { '@odata.id' => $path, Reading => 4800 };
  is( transport($fake)->get($path)->{Reading}, 4800, 'is found under the address the controller gave' );
};

subtest 'something that is not Redfish' => sub {
  my $fake = FakeiDRAC->new;
  delete $fake->doc('/redfish/v1')->{RedfishVersion};
  my $error = error_of { transport($fake)->get($system) };
  isa_ok( $error, 'WWW::iDRAC::Error::API' );
  like( "$error", qr/is Redfish enabled on this iDRAC\?/, 'says what to look at' );

  my $silent = FakeiDRAC->new;
  delete $silent->doc('/redfish/v1')->{Links};
  like( error_of { transport($silent)->get($system) }, qr/names no session collection/, 'a service root without a session collection' );
};

done_testing;
