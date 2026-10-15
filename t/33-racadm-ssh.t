#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# The I/O layer under the transport, against a stand-in for Net::OpenSSH:
# what it is asked for, how a failure is named, that the password does not
# leak, that a pinned host key is a file that goes away. No SSH is made.

BEGIN {
  package Net::OpenSSH;
  use Scalar::Util qw( dualvar );
  use Net::OpenSSH::Constants qw( OSSH_MASTER_FAILED OSSH_SLAVE_CMD_FAILED );
  our ( @NEW, @CAPTURE, %PLAN, $LIVE, $CHECKS );
  sub new {
    my ( $class, $host, %arg ) = @_;
    push @NEW, { host => $host, %arg };
    # what the ssh program of the master would have said, where it is asked to
    if ( defined $PLAN{master_stderr} && $arg{master_stderr_fh} ) {
      print { $arg{master_stderr_fh} } $PLAN{master_stderr};
      $arg{master_stderr_fh}->flush;
    }
    my $self = bless { error => $PLAN{connect_error} ? dualvar( OSSH_MASTER_FAILED, $PLAN{connect_error} ) : 0 }, $class;
    $LIVE++;
    return $self;
  }
  sub error { $_[0]{error} }
  sub capture2 {
    my ( $self, $opt, $command ) = @_;
    push @CAPTURE, { %$opt, command => $command };
    $self->{error} = $PLAN{exit_code} ? dualvar( OSSH_SLAVE_CMD_FAILED, 'child exited with code '.$PLAN{exit_code} )
                   : $PLAN{run_error} ? dualvar( OSSH_MASTER_FAILED, $PLAN{run_error} ) : 0;
    return ( $PLAN{out} // '', $PLAN{err} // '' );
  }
  sub check_master {
    my ( $self ) = @_;
    $CHECKS++;
    return 1 if $PLAN{master_alive} // 1;
    $self->{error} = dualvar( OSSH_MASTER_FAILED, 'master SSH connection broken' );
    return 0;
  }
  sub DESTROY { $LIVE-- }
  $INC{'Net/OpenSSH.pm'} = __FILE__;
}

use lib 't/lib';
use WWW::iDRAC::Racadm::SSH;

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

sub ssh { WWW::iDRAC::Racadm::SSH->new( host => 'idrac.example.org', username => 'root', password => 'S3cret', @_ ) }

sub reset_plan { @Net::OpenSSH::NEW = (); @Net::OpenSSH::CAPTURE = (); %Net::OpenSSH::PLAN = (); $Net::OpenSSH::CHECKS = 0 }

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

subtest 'what the ssh program said decides the cause' => sub {
  # what Net::OpenSSH 0.84 says for every master that ends before the login,
  # whatever ended it (measured against a closed port on 127.0.0.1)
  my $generic = 'unable to establish master SSH connection: bad password or master process exited unexpectedly';
  my %want = (
    "ssh: connect to host idrac.example.org port 22: Connection refused\n"                        => 'refused',
    "ssh: Could not resolve hostname idrac.example.org: Name or service not known\n"              => 'unreachable',
    "ssh: connect to host idrac.example.org port 22: No route to host\n"                          => 'unreachable',
    "Host key verification failed.\n"                                                             => 'host_key',
    "root\@idrac.example.org: Permission denied (keyboard-interactive,password).\n"              => 'auth',
  );
  for my $stderr ( sort keys %want ) {
    reset_plan();
    @Net::OpenSSH::PLAN{qw( connect_error master_stderr )} = ( $generic, $stderr );
    my $e = error_of { ssh()->run('x') };
    isa_ok( $e, 'WWW::iDRAC::Error::Network', $want{$stderr} );
    is( $e->cause, $want{$stderr}, 'the cause comes from what ssh printed, not from the generic message' );
    like( "$e", qr/\Q@{[ $stderr =~ s{\n}{}r ]}\E/, 'which is in the message' );
  }
  my $file = $Net::OpenSSH::NEW[0]{master_stderr_fh};
  ok( $file, 'the master writes its standard error into a file of ours' );

  reset_plan();
  $Net::OpenSSH::PLAN{connect_error} = $generic;
  my $e = error_of { ssh()->run('x') };
  is( $e->cause, 'other', 'with nothing on standard error the generic message is no refused password' );
  like( "$e", qr/master process exited unexpectedly/, 'and it is what the message says' );

  reset_plan();
  @Net::OpenSSH::PLAN{qw( connect_error master_stderr )} = ( $generic, "debug: sent password S3cret\nPermission denied\n" );
  $e = error_of { ssh()->run('x') };
  unlike( "$e", qr/S3cret/, 'a password in what ssh printed is not in the message' );

  reset_plan();
  $Net::OpenSSH::PLAN{master_stderr} = "Warning: Permanently added 'idrac.example.org' to the list of known hosts.\n";
  my $ssh = ssh();
  is( $ssh->run('x'), '', 'what ssh says about a working connection is no failure' );
  ok( $ssh->connected, 'connected' );
};

subtest 'a command that exits with a status that is not 0' => sub {
  reset_plan();
  @Net::OpenSSH::PLAN{qw( exit_code out )} = ( 1, "ERROR: RAC1033: The job cannot be deleted.\n" );
  my $ssh = ssh();
  is( $ssh->run('racadm jobqueue delete -i JID_1'), "ERROR: RAC1033: The job cannot be deleted.\n", 'returns what it printed, for racadm to judge' );
  ok( $ssh->connected, 'and keeps the connection' );
  is( $Net::OpenSSH::CHECKS, 1, 'after asking the master whether it is alive' );
  @Net::OpenSSH::PLAN{qw( exit_code out err )} = ( 1, '', "ERROR: on standard error\n" );
  is( $ssh->run('y'), "ERROR: on standard error\n", 'or what it printed to standard error' );
  @Net::OpenSSH::PLAN{qw( exit_code out err )} = ( 3, '', '' );
  my $e = error_of { $ssh->run('z') };
  isa_ok( $e, 'WWW::iDRAC::Error::Network', 'a command that fails and prints nothing' );
  like( "$e", qr/code 3/, 'says so' );
  is( $e->cause, 'other', 'cause other' );
  ok( $ssh->connected, 'the connection stays' );
  is( scalar @Net::OpenSSH::NEW, 1, 'one connection for all of it' );

  @Net::OpenSSH::PLAN{qw( exit_code master_alive out err )} = ( 255, 0, '', "Control socket connect: Connection refused\n" );
  $e = error_of { $ssh->run('w') };
  isa_ok( $e, 'WWW::iDRAC::Error::Network', 'a master that has gone' );
  ok( !$ssh->connected, 'drops the connection' );
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

subtest 'a known_hosts file' => sub {
  reset_plan();
  ssh( known_hosts => '/x' )->run('x');
  my @o = grep { $_ ne '-o' } @{ $Net::OpenSSH::NEW[0]{master_opts} };
  ok( ( grep { $_ eq 'UserKnownHostsFile=/x' } @o ), 'the file is the one to check against' );
  ok( ( grep { $_ eq 'GlobalKnownHostsFile=/dev/null' } @o ), 'and nothing else counts' );
  ok( ( grep { $_ eq 'StrictHostKeyChecking=yes' } @o ), 'strictly' );

  reset_plan();
  ssh()->run('x');
  @o = grep { $_ ne '-o' } @{ $Net::OpenSSH::NEW[0]{master_opts} };
  ok( !( grep { /KnownHostsFile/ } @o ), 'without one the known_hosts of the user are used' );
};

subtest 'options_from' => sub {
  my $o = sub { [ grep { $_ ne '-o' } @{ WWW::iDRAC::Racadm::SSH->options_from(@_) } ] };
  my $base = $o->( verify_host_key => 1 );
  ok( ( grep { $_ eq 'PreferredAuthentications=keyboard-interactive,password' } @$base ), 'password and keyboard-interactive only' );
  ok( ( grep { $_ eq 'PubkeyAuthentication=no' } @$base ), 'no key' );
  ok( ( grep { $_ eq 'NumberOfPasswordPrompts=1' } @$base ), 'one attempt' );
  my $off = $o->( verify_host_key => 0 );
  ok( ( grep { $_ eq 'PreferredAuthentications=keyboard-interactive,password' } @$off ), 'also without the host key check' );
  ok( ( grep { $_ eq 'UserKnownHostsFile=/dev/null' } @$off ), 'which writes no known_hosts' );
  my $extra = $o->( verify_host_key => 1, ssh_opts => ['Ciphers=aes128-ctr'] );
  is( $extra->[-1], 'Ciphers=aes128-ctr', 'the options of the caller come last' );
  isa_ok( error_of { WWW::iDRAC::Racadm::SSH->options_from( verify_host_key => 1, ssh_opts => ['ProxyCommand=x y'] ) }, 'WWW::iDRAC::Error::Validation', 'an option with a space' );
  isa_ok( error_of { WWW::iDRAC::Racadm::SSH->options_from( verify_host_key => 1, ssh_opts => ['ProxyCommand=a;b'] ) }, 'WWW::iDRAC::Error::Validation', 'an option with a ;' );
  isa_ok( error_of { WWW::iDRAC::Racadm::SSH->options_from( verify_host_key => 1, ssh_opts => ['nothing'] ) }, 'WWW::iDRAC::Error::Validation', 'an option without =' );
};

subtest 'known_hosts_line_from' => sub {
  my $line = sub { WWW::iDRAC::Racadm::SSH->known_hosts_line_from( 'h.example', 22, @_ ) };
  is( $line->("ssh-ed25519 AAAAC3Nz\n"), "h.example ssh-ed25519 AAAAC3Nz\n", 'a trailing newline is not part of the key' );
  is( $line->("ssh-ed25519 AAAAC3Nz \t\r\n"), "h.example ssh-ed25519 AAAAC3Nz\n", 'nor is trailing white space' );
  is( $line->('ssh-ed25519 AAAAC3Nz user@host'), "h.example ssh-ed25519 AAAAC3Nz\n", 'a comment is dropped' );
  is( WWW::iDRAC::Racadm::SSH->known_hosts_line_from( 'h.example', 2222, 'ssh-rsa AAAA==' ), "[h.example]:2222 ssh-rsa AAAA==\n", 'a port other than 22' );
  isa_ok( error_of { $line->(undef) }, 'WWW::iDRAC::Error::Validation', 'undef' );
  isa_ok( error_of { $line->('AAAA') }, 'WWW::iDRAC::Error::Validation', 'no type' );
  isa_ok( error_of { $line->("ssh-rsa AAAA\nother ssh-rsa BBBB") }, 'WWW::iDRAC::Error::Validation', 'two lines' );

  reset_plan();
  my $ssh = ssh( host_key => "ssh-ed25519 AAAAC3Nz\n", port => 2222 );
  $ssh->run('x');
  my @o = grep { $_ ne '-o' } @{ $Net::OpenSSH::NEW[0]{master_opts} };
  my ($file) = map { /\AUserKnownHostsFile=(.+)\z/ ? $1 : () } @o;
  open my $fh, '<', $file or die $!;
  is( do { local $/; <$fh> }, "[idrac.example.org]:2222 ssh-ed25519 AAAAC3Nz\n", 'through connect, the port is part of the name' );
  close $fh;
  $ssh->disconnect;
};

subtest 'a forked child does not touch the connection of its parent' => sub {
  reset_plan();
  my $ssh = ssh( host_key => 'ssh-ed25519 AAAAC3Nz' );
  $ssh->run('x');
  my ($file) = map { /\AUserKnownHostsFile=(.+)\z/ ? $1 : () } grep { $_ ne '-o' } @{ $Net::OpenSSH::NEW[0]{master_opts} };
  ok( $ssh->connected, 'connected' );
  $ssh->{_pid} = $$ + 1;    # as in a child forked after the object was made
  ok( !$ssh->connected, 'not from the process of a child' );
  is( $ssh->disconnect, 0, 'which cannot disconnect it' );
  is( $Net::OpenSSH::LIVE, 1, 'the client is still there' );
  ok( -e $file, 'and so is the host key file' );
  $ssh->{_pid} = $$;
  ok( $ssh->connected, 'connected again for its own process' );
  is( $ssh->disconnect, 1, 'which ends it' );
  is( $Net::OpenSSH::LIVE, 0, 'the client is gone' );
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
