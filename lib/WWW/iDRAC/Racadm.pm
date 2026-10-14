package WWW::iDRAC::Racadm;

# ABSTRACT: The racadm transport of WWW::iDRAC - what Redfish lacks on iDRAC 7 and 8

use Moo;
use Scalar::Util qw( blessed refaddr weaken );
use Types::Standard qw( ArrayRef Bool Int Maybe Str );
use WWW::iDRAC::Error::API;
use WWW::iDRAC::Error::Network;
use WWW::iDRAC::Error::Validation;
use namespace::autoclean;

our $VERSION = '0.001';

=synopsis

    my $racadm = $idrac->racadm;

    my $text = $racadm->run( get => 'BIOS.BiosBootSettings' );
    my ($block) = $racadm->blocks_from($text);
    print "$_->{name}=$_->{value}\n" for @{ $block->{entries} };

=description

The second transport. An iDRAC 7 and an iDRAC 8 have racadm, a command line
program of the controller, behind their SSH service; this class sends one
command and returns what it printed. BIOS attributes, the job queue and
virtual media are served over it by L<WWW::iDRAC::Bios>,
L<WWW::iDRAC::Jobs> and L<WWW::iDRAC::VirtualMedia>, and
C<< $idrac->capabilities->license >> reads the license through it.

It is the way out for what those classes do not cover, as
L<WWW::iDRAC::Redfish> is for Redfish. Nothing is translated here except
the errors: C<run> returns the text racadm printed, and the C<*_from>
functions turn that text into structures without any I/O.

racadm reports an error as text, with an exit status of 0, so every answer
is looked at: an C<ERROR:> line becomes L<WWW::iDRAC::Error::API> with the
code racadm printed in C<message_id>; a failure to connect, to verify the
host key or to log in becomes L<WWW::iDRAC::Error::Network> with a
C<cause>. Passwords appear in no message.

The connection is made on the first command and kept, with a single login
attempt, until L</logout>. The I/O sits in L<WWW::iDRAC::Racadm::SSH> and is
replaceable with L</runner>.

=cut

has host => ( is => 'ro', isa => Str, required => 1 );

=attr host

Required. The name or address of the controller, without a port.

=cut

has port => ( is => 'ro', isa => Int, default => 22 );

=attr port

The SSH port, 22 by default.

=cut

has username => ( is => 'ro', isa => Str, required => 1 );
has password => ( is => 'ro', isa => Str, required => 1 );

=attr username

=attr password

Required. Never part of a message, and never put on a command line of this
machine: the password goes to the SSH client through its terminal prompt.

=cut

has enabled => ( is => 'ro', isa => Bool, default => 1 );

=attr enabled

True by default. False says the caller does not want racadm used: the
capability classes served over it answer L<WWW::iDRAC::Error::Unsupported>
before anything is sent, and the license is not read.

=cut

has timeout => ( is => 'ro', isa => Int, default => 60 );

=attr timeout

Seconds without any traffic after which a connection attempt or a command is
given up, 60 by default. racadm is slow, a command such as C<get BIOS...> can
take ten seconds on its own.

=cut

has known_hosts     => ( is => 'ro', isa => Str, predicate => 'has_known_hosts' );
has host_key        => ( is => 'ro', isa => Str, predicate => 'has_host_key' );
has verify_host_key => ( is => 'ro', isa => Bool, default => 1 );
has ssh_opts        => ( is => 'ro', isa => ArrayRef [Str], default => sub { [] } );

=attr known_hosts

A C<known_hosts> file to check the host key against. Without it and without
L</host_key>, the one of the user running the program is used.

=attr host_key

The host key to expect, as one C<known_hosts> entry without the host name:
the type and the base64 key, for example C<ssh-ed25519 AAAA...>. Takes
precedence over every file; nothing else is accepted.

=attr verify_host_key

True by default: an unknown or changed host key ends the connection. False
accepts any key and is your decision to make, not a default. Not allowed
together with L</known_hosts> or L</host_key>.

=attr ssh_opts

Further C<-o> options for the SSH client, each as C<Name=value>, for a
controller that needs algorithms a current OpenSSH has switched off.
L</verify_host_key> and the login options cannot be overridden by them.

=cut

has runner => ( is => 'lazy', predicate => 'has_runner' );

sub _build_runner {
  my ( $self ) = @_;
  require WWW::iDRAC::Racadm::SSH;
  return WWW::iDRAC::Racadm::SSH->new(
    host            => $self->host,
    port            => $self->port,
    username        => $self->username,
    password        => $self->password,
    timeout         => $self->timeout,
    verify_host_key => $self->verify_host_key,
    ssh_opts        => $self->ssh_opts,
    ( $self->has_known_hosts ? ( known_hosts => $self->known_hosts ) : () ),
    ( $self->has_host_key    ? ( host_key    => $self->host_key )    : () )
  );
}

=attr runner

The object that does the I/O: C<run($command, $timeout)> returns what the
command printed or throws L<WWW::iDRAC::Error::Network>, C<connected> says
whether a connection is open, C<disconnect> closes it. The default is a
L<WWW::iDRAC::Racadm::SSH>. Tests, and an asynchronous twin, bring their own.

=cut

with 'WWW::iDRAC::Role::Transport';

sub transport_name { 'racadm' }

=method transport_name

C<racadm>, see L<WWW::iDRAC::Role::Transport>.

=cut

# the objects that may hold a connection, held weakly, for the END block below
my %LIVE;
our $PID = $$;

sub BUILD {
  my ( $self ) = @_;
  WWW::iDRAC::Error::Validation->throw( message => 'verify_host_key => 0 with known_hosts or host_key drops the check: either verify the host key or give it, not both' )
    if !$self->verify_host_key && ( $self->has_known_hosts || $self->has_host_key );
  WWW::iDRAC::Error::Validation->throw( message => 'known_hosts and host_key are two ways to say the same thing: give one' )
    if $self->has_known_hosts && $self->has_host_key;
  weaken( $LIVE{ refaddr $self } = $self );
  return;
}

# ---- translation, no I/O -------------------------------------------------

# the characters a value may be made of. Whatever racadm does with a quote, a
# backslash or the characters a shell reads is not known for every firmware,
# so a value with one is refused, not escaped.
my $SAFE_VALUE = qr/\A[A-Za-z0-9 _.:\/\@=,+%#-]*\z/;
my $BARE_WORD  = qr/\A[A-Za-z0-9_.:\/\@=,+%-]+\z/;

sub quote {
  my ( $class, $word ) = @_;
  WWW::iDRAC::Error::Validation->throw( message => 'a racadm argument is a plain string' )
    unless defined $word && !ref $word;
  WWW::iDRAC::Error::Validation->throw( message => 'a racadm argument is at most 512 characters' )
    if length $word > 512;
  WWW::iDRAC::Error::Validation->throw( message => 'a racadm argument may hold letters, digits, space and _ . : / @ = , + % # -, nothing else is passed to the controller' )
    unless $word =~ $SAFE_VALUE;
  return $word =~ $BARE_WORD ? $word : '"'.$word.'"';
}

=method quote

    my $word = WWW::iDRAC::Racadm->quote('my share');    # "my share"

One argument as the racadm command line takes it: as it is when it holds
only characters that need no quoting, in double quotes otherwise. A value
with a character outside letters, digits, space and C<_ . : / @ = , + % #
-> is L<WWW::iDRAC::Error::Validation>, because what racadm makes of a quote,
a backslash or a character a shell reads is not known for every firmware. The
message does not contain the value.

=cut

sub command_from {
  my ( $class, @word ) = @_;
  WWW::iDRAC::Error::Validation->throw( message => 'a racadm command needs a subcommand' ) unless @word;
  return join ' ', 'racadm', map { $class->quote($_) } @word;
}

=method command_from

    my $command = WWW::iDRAC::Racadm->command_from( get => 'BIOS.BiosBootSettings' );
    # racadm get BIOS.BiosBootSettings

The command line for a list of words, each one quoted by L</quote>. No I/O.

=cut

sub text_from {
  my ( $class, $raw ) = @_;
  return '' unless defined $raw && !ref $raw;
  ( my $text = $raw ) =~ s/\r//g;
  return $text;
}

=method text_from

What the controller printed, without carriage returns. No I/O.

=cut

# the first word of a line racadm prints for a result, like RAC1017 or SWC0242
my $CODE = qr/[A-Z]{2,5}[0-9]{1,5}/;

sub error_from {
  my ( $class, $raw ) = @_;
  my $text = $class->text_from($raw);
  my @lines = split /\n/, $text;
  shift @lines while @lines && $lines[0] !~ /\S/;
  return undef unless @lines;
  my ( $code, $message, $license );
  if ( $lines[0] =~ /\AERROR:\s*(?:($CODE)\s*:\s*)?(.*)\z/ ) {
    ( $code, $message ) = ( $1, $2 );
  }
  elsif ( my ( $coded, $said ) = $lines[0] =~ /\A($CODE)\s*:\s*(.*)\z/ ) {
    # RAC1017 and RAC1024 are successes; a coded line is an error when it says so
    return undef unless $said =~ /\b(?:invalid|not found|not supported|not allowed|not valid|failed|unable|denied|cannot)\b/i;
    ( $code, $message ) = ( $coded, $said );
  }
  else { return undef }
  my @rest = grep { /\S/ } @lines[ 1 .. $#lines ];
  for (@rest) { ( $license ) = /\ARequired License\s*--\s*(.+?)\s*\z/ unless defined $license }
  $message = join ' ', map { s/\A\s+|\s+\z//gr } grep { length $_ } $message, grep { !/\ARequired License\s*--/ } @rest;
  $message =~ s/\s+/ /g;
  return { code => $code, message => $message, license => $license };
}

=method error_from

    my $error = WWW::iDRAC::Racadm->error_from($text);

C<undef> when racadm printed no error. Otherwise a hash: C<code> (C<RAC1019>,
C<SWC0242>, or C<undef> when racadm printed none), C<message> (the text with
its line breaks undone) and C<license> (the license racadm names when it says
one is missing, as in C<Virtual Media>, else C<undef>). An error is a first
line that starts with C<ERROR:>, or a coded line like C<RAC992: Invalid job>
that says it failed. No I/O.

=cut

sub blocks_from {
  my ( $class, $raw ) = @_;
  my ( @blocks, $block );
  for my $line ( split /\n/, $class->text_from($raw) ) {
    if ( $line =~ /\A\[([A-Za-z][A-Za-z ]*)=([^\]]*)\]\s*\z/ ) {
      push @blocks, $block = { kind => $1, id => $2, entries => [] };
    }
    elsif ( $block && $line =~ /\A(#?)([A-Za-z][^=]*?)\s*=(.*)\z/ ) {
      my ( $ro, $name, $value ) = ( $1, $2, $3 );
      $value =~ s/\A\s+|\s+\z//g;
      # a value racadm shows in brackets is padded inside them
      $value =~ s/\A\[\s*(.*?)\s*\]\z/$1/;
      push @{ $block->{entries} }, { name => $name, value => $value, read_only => $ro ? 1 : 0 };
    }
  }
  return @blocks;
}

=method blocks_from

    my @blocks = WWW::iDRAC::Racadm->blocks_from($text);
    # ( { kind => 'Key', id => 'BIOS.Setup.1-1#BiosBootSettings',
    #     entries => [ { name => 'BootMode', value => 'Uefi', read_only => 0 }, ... ] } )

The C<[Key=...]> and C<[Job ID=...]> blocks racadm prints for C<get> and for
the job queue. An entry starting with C<#> is read-only; a value racadm puts
in brackets loses them and the padding inside them. No I/O.

=cut

# ---- I/O -----------------------------------------------------------------

sub run {
  my ( $self, @word ) = @_;
  my $command = $self->command_from(@word);
  my $text    = $self->text_from( $self->runner->run( $command, $self->timeout ) );
  my $error   = $self->error_from($text);
  if ($error) {
    # whatever racadm echoes, a password it was given is not part of an error
    my @secret = grep { defined && length } $self->password, map { $word[$_] } grep { $word[ $_ - 1 ] eq '-p' } 1 .. $#word;
    $error->{message} =~ s/\Q$_\E/***/g for @secret;
  }
  $self->api_error_class->throw(
    message     => 'racadm '.$word[0].' failed'.( defined $error->{code} ? ' ('.$error->{code}.')' : '' ).': '.$error->{message},
    http_status => undef,
    message_id  => $error->{code},
    api_message => $error->{message},
    resolution  => defined $error->{license} ? 'a license for '.$error->{license}.' is required' : undef
  ) if $error;
  return $text;
}

=method run

    my $text = $racadm->run( get => 'BIOS.BiosBootSettings' );
    $racadm->run( jobqueue => 'view', '-i', 'JID_123456789012' );

Sends C<racadm> and the words, quoted, and returns what it printed. Throws
L<WWW::iDRAC::Error::Validation> for an argument that cannot be sent safely
(before anything is sent), L<WWW::iDRAC::Error::Network> when the connection
cannot be made or is lost, and L<WWW::iDRAC::Error::API> when racadm printed
an error, with its code in C<message_id>. A missing license is C<SWC0242> and
the license in C<resolution>.

=cut

sub api_error_class { 'WWW::iDRAC::Error::API' }

=method api_error_class

The class racadm errors are thrown as; an asynchronous client overrides it.

=cut

sub connected { $_[0]->has_runner && $_[0]->runner->connected ? 1 : 0 }

=method connected

True while a connection is open.

=cut

sub logout {
  my ( $self ) = @_;
  return 0 unless $$ == $PID;
  return 0 unless $self->has_runner && $self->runner->connected;
  $self->runner->disconnect;
  return 1;
}

=method logout

Closes the connection, if there is one, and returns true when there was one.
An iDRAC allows only a few SSH sessions at a time. The object also does it
when it is destroyed, and every object still alive does it when the program
ends.

=cut

sub DEMOLISH {
  my ( $self ) = @_;
  local ( $@, $!, $? );
  delete $LIVE{ refaddr $self };
  eval { $self->logout };
  return;
}

END {
  local ( $@, $!, $? );
  return unless $$ == $PID;
  eval { $_->logout } for grep { defined } values %LIVE;
}

1;
