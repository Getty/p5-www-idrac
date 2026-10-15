#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

# The transport against a fake runner: what it sends, what it does with the
# answer, the errors, and that the connection ends.

use FakeRacadm;
use WWW::iDRAC::Racadm;

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

subtest 'run' => sub {
  my $fake    = FakeRacadm->new;
  my $racadm  = $fake->transport( timeout => 17 );
  is( $racadm->transport_name, 'racadm', 'its name' );
  ok( !$racadm->connected, 'not connected before the first command' );
  like( $racadm->run('getversion'), qr/iDRAC Version\s+= 2\.50/, 'the text racadm printed' );
  is_deeply( $fake->commands, ['racadm getversion'], 'the command line' );
  is_deeply( $fake->timeouts, [17], 'with the timeout of the transport' );
  ok( $racadm->connected, 'connected now' );
  is( $racadm->logout, 1, 'logout ends it' );
  is( $racadm->logout, 0, 'and only once' );
  ok( !$racadm->connected, 'not connected' );
};

subtest 'what racadm says is an error' => sub {
  my $racadm = FakeRacadm->new->transport;
  my $e = error_of { $racadm->run( get => 'BIOS.Nonexistent' ) };
  isa_ok( $e, 'WWW::iDRAC::Error::API', 'ERROR: with a code' );
  is( $e->message_id, 'RAC1020', 'the code' );
  ok( !defined $e->http_status, 'there is no HTTP status' );
  ok( $e->is_not_found, 'and it is a not found' );
  ok( !$e->is_unauthorized, 'not an unauthorized' );
  like( "$e", qr/\Aracadm get failed \(RAC1020\): No objects are available/, 'the message' );

  $e = error_of { $racadm->run( get => 'BIOS.BiosBootSettings.Nope' ) };
  is( $e->message_id, 'RAC1019', 'RAC1019' );
  ok( $e->is_not_found, 'is a not found too' );

  $e = error_of { $racadm->run( jobqueue => 'view', '-i', 'JID_000000000099' ) };
  is( $e->message_id, 'RAC992', 'an invalid job, which has no ERROR: in front of it' );
  ok( $e->is_not_found, 'is a not found' );

  is( error_of { $racadm->run( qw( get iDRAC.VirtualMedia ) ) }, undef, 'the same command is fine with a license' );
  $e = error_of { FakeRacadm->new( licensed => 0 )->transport->run( qw( get iDRAC.VirtualMedia ) ) };
  is( $e->message_id, 'SWC0242', 'a missing license' );
  like( $e->resolution, qr/Virtual Media/, 'names it' );
  ok( !$e->is_not_found, 'and is no not found' );

  my $unsupported = error_of { $racadm->run( 'explode' ) };
  isa_ok( $unsupported, 'WWW::iDRAC::Error::API', 'an invalid subcommand' );
  is( $unsupported->message_id, undef, 'without a code' );
};

subtest 'nothing unsafe is sent' => sub {
  my $fake   = FakeRacadm->new;
  my $racadm = $fake->transport;
  for my $words ( [ get => 'BIOS.A; racadm serveraction powerdown' ], [ get => "x\ny" ], [ set => 'BIOS.A.B', 'a"b' ], [], [ 'get', undef ] ) {
    isa_ok( error_of { $racadm->run(@$words) }, 'WWW::iDRAC::Error::Validation', 'refused: '.scalar @$words.' words' );
  }
  is_deeply( $fake->commands, [], 'and nothing reached the runner' );
};

subtest 'the password is no part of a message' => sub {
  my $secret = 'S3cretPw';
  my $fake   = FakeRacadm->new( replies => {
    'racadm remoteimage -c -u share -p '.$secret.' -l //h/s/a.iso' => "ERROR: RAC1100: Login failed for share with $secret as the password.\n",
    'racadm getversion'                                           => "ERROR: RAC1100: the login $secret was refused.\n"
  } );
  my $racadm = $fake->transport( password => $secret );
  my $e = error_of { $racadm->run( qw( remoteimage -c -u share -p ), $secret, qw( -l //h/s/a.iso ) ) };
  isa_ok( $e, 'WWW::iDRAC::Error::API' );
  unlike( "$e", qr/\Q$secret\E/, 'the password of the share is not in it' );
  unlike( $e->api_message, qr/\Q$secret\E/, 'nor in the api_message' );
  like( "$e", qr/\*\*\*/, 'something stands in its place' );
  $e = error_of { $racadm->run('getversion') };
  unlike( "$e", qr/\Q$secret\E/, 'nor the one of the login' );
};

subtest 'network errors pass through' => sub {
  my $down = WWW::iDRAC::Error::Network->new( message => 'connecting to idrac.test:22 over SSH failed: Connection refused', cause => 'refused' );
  my $racadm = FakeRacadm->new( fail => $down )->transport;
  my $e = error_of { $racadm->run('getversion') };
  isa_ok( $e, 'WWW::iDRAC::Error::Network' );
  is( $e->cause, 'refused', 'with its cause' );
};

subtest 'construction' => sub {
  my %base = ( host => 'idrac.example.org', username => 'root', password => 'calvin' );
  my $make = sub { WWW::iDRAC::Racadm->new( %base, @_ ) };
  isa_ok( $make->(), 'WWW::iDRAC::Racadm' );
  is( $make->()->port, 22, 'port 22' );
  is( $make->()->timeout, 60, 'timeout 60' );
  ok( $make->()->verify_host_key, 'the host key is verified' );
  ok( $make->()->enabled, 'enabled' );
  isa_ok( error_of { $make->( verify_host_key => 0, host_key => 'ssh-ed25519 AAAA' ) }, 'WWW::iDRAC::Error::Validation', 'no check and a key' );
  isa_ok( error_of { $make->( verify_host_key => 0, known_hosts => '/etc/h' ) }, 'WWW::iDRAC::Error::Validation', 'no check and a file' );
  isa_ok( error_of { $make->( known_hosts => '/etc/h', host_key => 'ssh-ed25519 AAAA' ) }, 'WWW::iDRAC::Error::Validation', 'a file and a key' );
  ok( !$make->( verify_host_key => 0 )->verify_host_key, 'no check, on request' );
  my $default = $make->()->runner;
  isa_ok( $default, 'WWW::iDRAC::Racadm::SSH', 'the default runner' );
  ok( !$default->connected, 'which does not connect before it is used' );

  my $full = $make->(
    port => 2222, timeout => 9, host_key => 'ssh-ed25519 AAAA', ssh_opts => ['KexAlgorithms=+diffie-hellman-group14-sha1']
  )->runner;
  is( $full->host, 'idrac.example.org', 'the runner gets the host' );
  is( $full->username, 'root', 'the user' );
  is( $full->password, 'calvin', 'the password' );
  is( $full->port, 2222, 'the port' );
  is( $full->timeout, 9, 'the timeout' );
  is( $full->host_key, 'ssh-ed25519 AAAA', 'the host key' );
  ok( !$full->has_known_hosts, 'and no known_hosts' );
  ok( $full->verify_host_key, 'verification stays on' );
  is_deeply( $full->ssh_opts, ['KexAlgorithms=+diffie-hellman-group14-sha1'], 'the ssh options' );

  my $file = $make->( known_hosts => '/etc/idrac_hosts' )->runner;
  is( $file->known_hosts, '/etc/idrac_hosts', 'a known_hosts file' );
  ok( !$file->has_host_key, 'and no host key' );
  my $open = $make->( verify_host_key => 0 )->runner;
  ok( !$open->verify_host_key, 'verify_host_key => 0 reaches the runner' );
  is_deeply( $open->ssh_opts, [], 'no ssh options by default' );
  ok( !$open->has_known_hosts && !$open->has_host_key, 'nothing pinned' );

  for my $bad ( [ port => 'ssh' ], [ port => '2.5' ], [ timeout => 'soon' ], [ timeout => undef ], [ ssh_opts => 'A=b' ], [ verify_host_key => [] ] ) {
    ok( !eval { $make->( $bad->[0] => $bad->[1] ); 1 }, 'refused: '.$bad->[0].' => '.( $bad->[1] // 'undef' ) );
  }
};

subtest 'api_error_class is the hook for the class racadm errors are thrown as' => sub {
  {
    package My::Error::API;
    our @ISA = ('WWW::iDRAC::Error::API');
  }
  {
    package My::Racadm;
    our @ISA = ('WWW::iDRAC::Racadm');
    sub api_error_class { 'My::Error::API' }
  }
  my $fake = FakeRacadm->new;
  my $racadm = My::Racadm->new( host => 'idrac.test', username => 'root', password => 'calvin', runner => $fake );
  my $e = error_of { $racadm->run( get => 'BIOS.Nonexistent' ) };
  isa_ok( $e, 'My::Error::API', 'the error is of the class the hook names' );
  is( $e && $e->message_id, 'RAC1020', 'with its code' );
};

subtest 'the process that made the object ends its connection' => sub {
  my $fake   = FakeRacadm->new;
  my $racadm = $fake->transport;
  $racadm->run('getversion');
  $racadm->run('getversion');
  $racadm->{_pid} = $$ + 1;    # as in a child forked after the object was made
  is( $racadm->logout, 0, 'one made in another process does not' );
  ok( $fake->connected, 'and the connection stays' );
  $racadm->{_pid} = $$;
  is( $racadm->logout, 1, 'until its own process ends it' );
};

subtest 'an error that is not on the first line' => sub {
  my $fake = FakeRacadm->new( replies => { 'racadm set BIOS.A.B x' => "[Key=BIOS.Setup.1-1#A]\nERROR: RAC1019: The specified object is not supported.\n" } );
  my $e = error_of { $fake->transport->run( set => 'BIOS.A.B', 'x' ) };
  isa_ok( $e, 'WWW::iDRAC::Error::API', 'is an error' );
  is( $e && $e->message_id, 'RAC1019', 'with its code' );
};

subtest 'the connection ends with the object' => sub {
  my $fake = FakeRacadm->new;
  {
    my $racadm = $fake->transport;
    $racadm->run('getversion');
    ok( $fake->connected, 'open inside the scope' );
  }
  ok( !$fake->connected, 'closed when the transport goes away' );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
