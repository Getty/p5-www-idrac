#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# The I/O layer under the transport, against a stand-in for Net::OpenSSH:
# what it is asked for, how a failure is named, that the password does not
# leak, that a pinned host key is a file that goes away. No SSH is made.

BEGIN {
  package Net::OpenSSH;
  our ( @NEW, @CAPTURE, %PLAN, $LIVE );
  sub new {
    my ( $class, $host, %arg ) = @_;
    push @NEW, { host => $host, %arg };
    my $self = bless { error => $PLAN{connect_error} // 0 }, $class;
    $LIVE++;
    return $self;
  }
  sub error { $_[0]{error} }
  sub capture2 {
    my ( $self, $opt, $command ) = @_;
    push @CAPTURE, { %$opt, command => $command };
    $self->{error} = $PLAN{run_error} // 0;
    return ( $PLAN{out} // '', $PLAN{err} // '' );
  }
  sub DESTROY { $LIVE-- }
  $INC{'Net/OpenSSH.pm'} = __FILE__;
}

use lib 't/lib';
use WWW::iDRAC::Racadm::SSH;

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

sub ssh { WWW::iDRAC::Racadm::SSH->new( host => 'idrac.example.org', username => 'root', password => 'S3cret', @_ ) }

sub reset_plan { @Net::OpenSSH::NEW = (); @Net::OpenSSH::CAPTURE = (); %Net::OpenSSH::PLAN = () }

subtest 'run' => sub {
  reset_plan();
  $Net::OpenSSH::PLAN{out} = "hello\n";
  my $ssh = ssh( port => 2222, timeout => 33 );
  ok( !$ssh->connected, 'not connected' );
  is( $ssh->run( 'racadm getversion', 12 ), "hello\n", 'the output' );
  my $new = $Net::OpenSSH::NEW[0];
  is( $new->{host}, 'idrac.example.org', 'the host' );
  is( $new->{port}, 2222, 'the port' );
  is( $new->{user}, 'root', 'the user' );
  is( $new->{password}, 'S3cret', 'the password goes to the client, as an option of it' );
  is( $new->{timeout}, 33, 'the timeout' );
  ok( $new->{kill_ssh_on_timeout}, 'a hung client is killed' );
  my @o = grep { $_ ne '-o' } @{ $new->{master_opts} };
  ok( ( grep { $_ eq 'StrictHostKeyChecking=yes' } @o ), 'strict' );
  is_deeply( $Net::OpenSSH::CAPTURE[0], { timeout => 12, command => 'racadm getversion' }, 'one string, with the timeout' );
  ok( $ssh->connected, 'connected' );
  $ssh->run('racadm getversion');
  is( scalar @Net::OpenSSH::NEW, 1, 'one connection for two commands' );
  is( $Net::OpenSSH::CAPTURE[1]{timeout}, 33, 'the default timeout' );
  is( $ssh->disconnect, 1, 'disconnect' );
  is( $ssh->disconnect, 0, 'once' );
  is( $Net::OpenSSH::LIVE, 0, 'and the client is gone' );
};

subtest 'what is printed to standard error' => sub {
  reset_plan();
  @Net::OpenSSH::PLAN{qw( out err )} = ( '', "only the error\n" );
  is( ssh()->run('x'), "only the error\n", 'when that is all there is' );
  @Net::OpenSSH::PLAN{qw( out err )} = ( "out\n", "err\n" );
  is( ssh()->run('x'), "out\n", 'standard output wins' );
};

subtest 'failures' => sub {
  my %want = (
    'Connection refused'                          => 'refused',
    'Host key verification failed.'               => 'host_key',
    'Permission denied (keyboard-interactive).'   => 'auth',
    'the command timed out'                       => 'timeout'
  );
  for my $message ( sort keys %want ) {
    reset_plan();
    $Net::OpenSSH::PLAN{connect_error} = 'connection failed: '.$message.' for S3cret';
    my $e = error_of { ssh()->run('x') };
    isa_ok( $e, 'WWW::iDRAC::Error::Network', $message );
    is( $e->cause, $want{$message}, 'the cause' );
    unlike( "$e", qr/S3cret/, 'the password is not in the message' );
    like( "$e", qr/idrac\.example\.org:22/, 'the place is' );
  }
  reset_plan();
  $Net::OpenSSH::PLAN{run_error} = 'command timed out';
  my $ssh = ssh();
  my $e   = error_of { $ssh->run('x') };
  is( $e->cause, 'timeout', 'a command that times out' );
  ok( !$ssh->connected, 'and the connection is not trusted afterwards' );
  $Net::OpenSSH::PLAN{run_error} = 0;
  is( $ssh->run('y'), '', 'the next command connects again' );
  is( scalar @Net::OpenSSH::NEW, 2, 'with a new connection' );
};

subtest 'a pinned host key' => sub {
  reset_plan();
  my $ssh = ssh( host_key => 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq', port => 22 );
  $ssh->run('x');
  my @o = grep { $_ ne '-o' } @{ $Net::OpenSSH::NEW[0]{master_opts} };
  my ($file) = map { /\AUserKnownHostsFile=(.+)\z/ ? $1 : () } @o;
  ok( defined $file, 'a known_hosts file is named' );
  ok( -e $file, 'which exists while connected' );
  open my $fh, '<', $file or die $!;
  is( do { local $/; <$fh> }, "idrac.example.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq\n", 'and holds the key for this host' );
  close $fh;
  ok( ( grep { $_ eq 'GlobalKnownHostsFile=/dev/null' } @o ), 'nothing else counts' );
  $ssh->disconnect;
  ok( !-e $file, 'and is gone after disconnect' );
  isa_ok( error_of { ssh( host_key => "ssh-rsa AAAA\nevil ssh-rsa BBBB" )->run('x') }, 'WWW::iDRAC::Error::Validation', 'a key with a second line' );

  reset_plan();
  ssh( verify_host_key => 0 )->run('x');
  my @open = grep { $_ ne '-o' } @{ $Net::OpenSSH::NEW[0]{master_opts} };
  ok( ( grep { $_ eq 'StrictHostKeyChecking=no' } @open ), 'off only on request' );
};

subtest 'it ends with the object' => sub {
  reset_plan();
  {
    my $ssh = ssh();
    $ssh->run('x');
    is( $Net::OpenSSH::LIVE, 1, 'open' );
  }
  is( $Net::OpenSSH::LIVE, 0, 'closed' );
};

done_testing;
