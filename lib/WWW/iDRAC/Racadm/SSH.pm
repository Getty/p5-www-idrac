package WWW::iDRAC::Racadm::SSH;

# ABSTRACT: The SSH I/O under WWW::iDRAC::Racadm, over the OpenSSH client

use Moo;
use File::Temp ();
use Net::OpenSSH;
use Net::OpenSSH::Constants qw( OSSH_SLAVE_CMD_FAILED );
use Types::Standard qw( ArrayRef Bool Int Str );
use WWW::iDRAC::Error::Network;
use WWW::iDRAC::Error::Validation;
use namespace::autoclean;

our $VERSION = '0.001';

=synopsis

    my $ssh = WWW::iDRAC::Racadm::SSH->new(
      host => 'idrac.example.org', username => 'root', password => $pw,
      host_key => 'ssh-ed25519 AAAA...',
    );
    print $ssh->run( 'racadm getversion', 30 );
    $ssh->disconnect;

=description

All the I/O of L<WWW::iDRAC::Racadm> is here and nothing else: one SSH
connection made through L<Net::OpenSSH>, which drives the C<ssh> program of
the machine, so the algorithms, the host key checking and the user's
C<ssh_config> are those of the installed OpenSSH. Password login needs
L<IO::Pty>, which L<Net::OpenSSH> uses for the prompt.

Where the user's own C<known_hosts> is not wanted, L</host_key> or
L</known_hosts> says what to check against. The check is on unless
L</verify_host_key> is false.

An SSH client is a program that is not part of this distribution's tests;
the unit tests replace this class through L<WWW::iDRAC::Racadm/runner>. The
pure part, what goes on the command line of the client, is L</options_from>.

=cut

has host            => ( is => 'ro', isa => Str, required => 1 );
has port            => ( is => 'ro', isa => Int, default => 22 );
has username        => ( is => 'ro', isa => Str, required => 1 );
has password        => ( is => 'ro', isa => Str, required => 1 );
has timeout         => ( is => 'ro', isa => Int, default => 60 );
has known_hosts     => ( is => 'ro', isa => Str, predicate => 'has_known_hosts' );
has host_key        => ( is => 'ro', isa => Str, predicate => 'has_host_key' );
has verify_host_key => ( is => 'ro', isa => Bool, default => 1 );
has ssh_opts        => ( is => 'ro', isa => ArrayRef [Str], default => sub { [] } );

=attr host

=attr port

=attr username

=attr password

=attr timeout

=attr known_hosts

=attr host_key

=attr verify_host_key

=attr ssh_opts

As described at L<WWW::iDRAC::Racadm>.

=cut

has _ssh        => ( is => 'rw', clearer => '_clear_ssh' );
has _key_file   => ( is => 'rw' );
has _pid        => ( is => 'ro', default => sub { $$ } );

sub known_hosts_line_from {
  my ( $class, $host, $port, $key ) = @_;
  # the newline at the end of a pasted key is not part of it; any other is
  $key =~ s/\s+\z// if defined $key && !ref $key;
  WWW::iDRAC::Error::Validation->throw( message => 'host_key is the type and the base64 key, like: ssh-ed25519 AAAA...' )
    unless defined $key && !ref $key && $key =~ /\A[ \t]*([A-Za-z0-9@.-]+)[ \t]+([A-Za-z0-9+\/]+={0,2})(?:[ \t][^\r\n]*)?\z/;
  my ( $type, $blob ) = ( $1, $2 );
  my $name = !defined $port || $port == 22 ? $host : '['.$host.']:'.$port;
  return join( ' ', $name, $type, $blob )."\n";
}

=method known_hosts_line_from

    my $line = WWW::iDRAC::Racadm::SSH->known_hosts_line_from( $host, $port, 'ssh-ed25519 AAAA...' );

The C<known_hosts> line that pins a host key to this host and port. A key in
another shape is L<WWW::iDRAC::Error::Validation>. No I/O.

=cut

sub options_from {
  my ( $class, %arg ) = @_;
  my @option = (
    # one attempt: a wrong password must not count against the lockout
    # of the controller more than once
    'NumberOfPasswordPrompts=1',
    'PreferredAuthentications=keyboard-interactive,password',
    'PubkeyAuthentication=no'
  );
  if ( !$arg{verify_host_key} ) {
    push @option, 'StrictHostKeyChecking=no', 'UserKnownHostsFile=/dev/null';
  }
  elsif ( defined $arg{key_file} ) {
    push @option, 'StrictHostKeyChecking=yes', 'UserKnownHostsFile='.$arg{key_file}, 'GlobalKnownHostsFile=/dev/null';
  }
  elsif ( defined $arg{known_hosts} ) {
    push @option, 'StrictHostKeyChecking=yes', 'UserKnownHostsFile='.$arg{known_hosts}, 'GlobalKnownHostsFile=/dev/null';
  }
  else {
    push @option, 'StrictHostKeyChecking=yes';
  }
  for my $extra ( @{ $arg{ssh_opts} || [] } ) {
    WWW::iDRAC::Error::Validation->throw( message => 'an ssh_opts entry is Name=value, without spaces' )
      unless $extra =~ /\A[A-Za-z0-9]+=[^\s'"`\;|&<>]+\z/;
    push @option, $extra;
  }
  return [ map { ( -o => $_ ) } @option ];
}

=method options_from

    my $master_opts = WWW::iDRAC::Racadm::SSH->options_from(
      verify_host_key => 1, known_hosts => $path, ssh_opts => ['KexAlgorithms=+diffie-hellman-group14-sha1']
    );

The options for the SSH client as a list of C<-o> pairs. Always: one
password attempt, password and keyboard-interactive login and no key, and
strict host key checking, unless C<verify_host_key> is false. With a pinned
key or a C<known_hosts> file, only that file is consulted: the global
C<known_hosts> is switched off (C<GlobalKnownHostsFile=/dev/null>). The
options the caller adds come after those; ssh uses the first value it is
given for an option, so they do not override the ones fixed here, but an
option not fixed here is the caller's to set. An entry that is not
C<Name=value>, without spaces or shell characters, is
L<WWW::iDRAC::Error::Validation>; the connection is the first thing to call
this, so that is where it is thrown. No I/O.

=cut

sub cause_from {
  my ( $class, $message ) = @_;
  return 'other' unless defined $message;
  return 'refused'     if $message =~ /connection refused/i;
  return 'unreachable' if $message =~ /no route to host|network is unreachable|could not resolve|name or service not known|name resolution|connect to host .* timed out/i;
  return 'host_key'    if $message =~ /host key verification failed|remote host identification has changed|host key for .* has changed|no .* host key is known/i;
  # not "bad password": Net::OpenSSH says that for every master that ends
  # before the login, whatever ended it
  return 'auth'        if $message =~ /permission denied|authentication failed|login incorrect|too many authentication failures/i;
  return 'timeout'     if $message =~ /timed? ?out/i;
  return 'other';
}

=method cause_from

    my $cause = WWW::iDRAC::Racadm::SSH->cause_from($message);

C<refused>, C<unreachable>, C<host_key>, C<auth>, C<timeout> or C<other>
for what the SSH client said, the C<cause> of L<WWW::iDRAC::Error::Network>.
No I/O.

=cut

sub _fail {
  my ( $self, $what, $message, $cause ) = @_;
  my $password = $self->password;
  $message = 'unknown error' unless defined $message && length $message;
  $message =~ s/\Q$password\E/***/g if length $password;
  $message =~ s/\s+/ /g;
  $message =~ s/\A | \z//g;
  $cause //= $self->cause_from($message);
  WWW::iDRAC::Error::Network->throw(
    message => $what.' '.$self->host.':'.$self->port.' over SSH failed: '.$message,
    cause   => $cause
  );
}

sub connect {
  my ( $self ) = @_;
  return $self->_ssh if $self->_ssh;
  my ( $key_file, $known_hosts );
  if ( $self->verify_host_key ) {
    if ( $self->has_host_key ) {
      my $line = $self->known_hosts_line_from( $self->host, $self->port, $self->host_key );
      $key_file = File::Temp->new( TEMPLATE => 'idrac-known-hosts-XXXXXX', TMPDIR => 1 );
      print {$key_file} $line;
      $key_file->flush;
      $self->_key_file($key_file);
    }
    elsif ( $self->has_known_hosts ) {
      $known_hosts = $self->known_hosts;
    }
  }
  # Net::OpenSSH says "bad password or master process exited unexpectedly"
  # for every master that ends before the login; why it ended is what the
  # ssh program printed. A file only this user can read, gone with $stderr.
  my $stderr = File::Temp->new( TEMPLATE => 'idrac-ssh-stderr-XXXXXX', TMPDIR => 1 );
  my $ssh = Net::OpenSSH->new(
    $self->host,
    port                => $self->port,
    user                => $self->username,
    password            => $self->password,
    timeout             => $self->timeout,
    kill_ssh_on_timeout => 1,
    master_stderr_fh    => $stderr,
    master_opts         => $self->options_from(
      verify_host_key => $self->verify_host_key,
      known_hosts     => $known_hosts,
      key_file        => $key_file ? $key_file->filename : undef,
      ssh_opts        => $self->ssh_opts
    )
  );
  if ( my $error = $ssh->error ) {
    seek $stderr, 0, 0;
    my $said = do { local $/; <$stderr> } // '';
    $said =~ s/\A\s+|\s+\z//g;
    my $cause = $self->cause_from($said);
    $cause = $self->cause_from("$error") if $cause eq 'other';
    $self->_fail( 'connecting to', length $said ? $said : "$error", $cause );
  }
  return $self->_ssh($ssh);
}

=method connect

Opens the connection if it is not open, and returns the client. Throws
L<WWW::iDRAC::Error::Network> with the C<cause> of the failure; the message
holds what the SSH client printed, or what L<Net::OpenSSH> said where it
printed nothing, with the password, if it is in there, replaced.

=cut

sub run {
  my ( $self, $command, $timeout ) = @_;
  my $ssh = $self->connect;
  # one string: it reaches the controller as it is, quoted by the caller
  my ( $out, $err ) = $ssh->capture2( { timeout => $timeout // $self->timeout }, $command );
  $out = '' unless defined $out;
  $out = $err if !length $out && defined $err;
  my $error = $ssh->error or return $out;
  # a command that exits with a status that is not 0 over a connection that
  # is still there: what it printed says why, and racadm judges that
  if ( $error == OSSH_SLAVE_CMD_FAILED && $ssh->check_master ) {
    return $out if length $out;
    $self->_fail( 'running a command on', 'the command failed ('.$error.') and printed nothing', 'other' );
  }
  # the connection is of no use after this
  $error = $ssh->error || $error;
  $self->_clear_ssh;
  $self->_fail( 'running a command on', "$error" );
}

=method run

    my $text = $ssh->run( 'racadm getversion', 30 );

Sends one command line and returns what it printed to standard output, or to
standard error when that was all. racadm prints its errors as text with an
exit status of 0; this method does not look at them, that is
L<WWW::iDRAC::Racadm/run>. A command that exits with another status returns
what it printed as well, and the connection stays, as long as the connection
is still there; one that printed nothing is L<WWW::iDRAC::Error::Network>
with the cause C<other>.

=cut

sub connected { $_[0]->_ssh && $$ == $_[0]->_pid ? 1 : 0 }

=method connected

True while the connection is open in this process.

=cut

sub disconnect {
  my ( $self ) = @_;
  return 0 unless $self->_ssh;
  return 0 unless $$ == $self->_pid;
  # Net::OpenSSH ends its master connection when it goes away
  $self->_clear_ssh;
  $self->_key_file(undef);
  return 1;
}

=method disconnect

Closes the connection and removes the file of a pinned host key. True when
there was a connection.

=cut

sub DEMOLISH {
  my ( $self ) = @_;
  local ( $@, $!, $? );
  eval { $self->disconnect };
  return;
}

1;
