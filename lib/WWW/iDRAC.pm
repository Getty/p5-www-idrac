package WWW::iDRAC;

# ABSTRACT: Perl client for Dell iDRAC - inventory, power, sensors, logs, BIOS, jobs and virtual media

use Moo;
use LWP::UserAgent;
use Types::Standard qw( ArrayRef Bool HashRef InstanceOf Int Maybe Object Str );
use WWW::iDRAC::Bios;
use WWW::iDRAC::Capabilities;
use WWW::iDRAC::Error;
use WWW::iDRAC::Error::API;
use WWW::iDRAC::Error::Network;
use WWW::iDRAC::Error::Unsupported;
use WWW::iDRAC::Error::Validation;
use WWW::iDRAC::Jobs;
use WWW::iDRAC::Logs;
use WWW::iDRAC::Manager;
use WWW::iDRAC::Power;
use WWW::iDRAC::Racadm;
use WWW::iDRAC::Redfish;
use WWW::iDRAC::Sensors;
use WWW::iDRAC::System;
use WWW::iDRAC::VirtualMedia;
use namespace::autoclean;

our $VERSION = '0.001';

=synopsis

    use WWW::iDRAC;

    my $idrac = WWW::iDRAC->new(
      host            => 'idrac-t330.example.org',
      username        => 'root',
      password        => $ENV{IDRAC_PASSWORD},
      ssl_fingerprint => 'sha256$5f2c...',     # or ssl_ca_file, or verify_ssl => 0
    );

    my $cap = $idrac->capabilities;
    printf "iDRAC %s, firmware %s\n", $cap->generation // '?', $cap->firmware // '?';

    print $idrac->system->info->{service_tag}, "\n";
    print $_->{name}, ': ', $_->{celsius} // '-', "\n" for @{ $idrac->sensors->temperatures };
    print $_->{created}, ' ', $_->{message}, "\n" for @{ $idrac->logs->sel( limit => 10 ) };

    $idrac->power->off;
    $idrac->power->off( force => 1 ) unless $idrac->power->wait_for( 'off', timeout => 300 );

    # what Redfish lacks on an iDRAC 7 or 8 comes over SSH, with racadm
    print $idrac->bios->get('BiosBootSettings.BootMode'), "\n";
    print $_->{id}, ' ', $_->{status}, "\n" for @{ $idrac->jobs->list };

    # undef where racadm is off or the SSH port is closed; a refused login
    # or host key throws WWW::iDRAC::Error::Network
    print $idrac->capabilities->license // '?', "\n";

    # what the facade does not cover yet
    my $chassis = $idrac->redfish->get('/redfish/v1/Chassis');

    $idrac->logout;

=description

A client for the management controller of Dell PowerEdge servers. The
methods are cut by what you want to know or do, not by protocol: you ask for
C<< $idrac->system->info >> and do not care how the answer is fetched. In
this version most of it is fetched over Redfish, and what Redfish lacks on an
iDRAC 7 or 8 (BIOS attributes, the job queue, virtual media, the license) over
racadm on the SSH service of the controller.

The methods return plain hashes with fixed keys, not Redfish documents. For
everything they do not cover there is L</redfish>, which hands out the raw
documents, and L</racadm>, which hands out what racadm printed.

What a controller can do depends on its generation, its firmware and its
license. A method this controller cannot serve throws
L<WWW::iDRAC::Error::Unsupported> before anything is sent.

=head2 SSH and racadm

BIOS, jobs and virtual media are served over racadm through SSH, which is
reached with the same C<username> and C<password> unless C<ssh_username>
and C<ssh_password> say otherwise. SSH is only used when one of those methods
is called, when C<< capabilities->supports >> is asked about one of them, or
when the license is read; the Redfish classes never touch it.
C<< ssh => 0 >> switches it off: those methods are then
L<WWW::iDRAC::Error::Unsupported> and no connection is made. The SSH side needs the
C<ssh> program of OpenSSH and L<Net::OpenSSH> on this machine, with
L<IO::Pty> for the password prompt, and the SSH service switched on at the
iDRAC.

The host key is checked: L</ssh_host_key> pins it, L</ssh_known_hosts> names
a file, and without either the C<known_hosts> of the user is used. A key it
does not know ends the connection.  C<< ssh_verify_host_key => 0 >> turns the
check off and is your decision to make, not a default. See
L<WWW::iDRAC::Racadm>.

B<Nothing that writes over racadm has run against hardware.>
C<< bios->set >> and C<commit>, C<< jobs->delete >> and
C<< virtual_media->connect >> and C<disconnect> are tested against a fake only;
what reads has run against an iDRAC 7 and an iDRAC 8.

=head2 Certificates

An iDRAC ships with a self-signed certificate issued to a name that is not
the address you reach it under. Verification is on anyway. L</ssl_fingerprint>
is the option that fits such a certificate, because a pinned certificate is
accepted whatever name is in it; L</ssl_ca_file> fits a controller that was
given a proper certificate. C<< verify_ssl => 0 >> turns the check off and
is your decision to make, not a default.

WWW::iDRAC does not lower TLS versions or ciphers. A controller that speaks
only what a current OpenSSL refuses needs newer firmware, or your own
settings in L</ssl_opts>.

=cut

has host => (
  is  => 'ro',
  isa => Maybe [Str],
);

=attr host

Required. The name or address of the iDRAC, optionally with C<:port>.

=cut

has username => ( is => 'ro', isa => Maybe [Str] );
has password => ( is => 'ro', isa => Maybe [Str] );

=attr username

=attr password

Required.

=cut

has session => (
  is      => 'ro',
  isa     => Bool,
  default => 1
);

=attr session

True by default: one Redfish session for all requests. False sends the
credentials with every request and creates no session.

=cut

has verify_ssl => (
  is      => 'ro',
  isa     => Bool,
  default => 1
);

=attr verify_ssl

True by default. False accepts any certificate.

=cut

has ssl_ca_file     => ( is => 'ro', isa => Str, predicate => 'has_ssl_ca_file' );
has ssl_fingerprint => ( is => 'ro', isa => Str, predicate => 'has_ssl_fingerprint' );

=attr ssl_ca_file

A file with the CA that signed the certificate of the iDRAC.

=attr ssl_fingerprint

The fingerprint of the certificate, as L<IO::Socket::SSL> takes it:
C<sha256$> followed by the hex digits. A certificate with this fingerprint
is accepted without any further check.

=cut

has ssl_opts => (
  is      => 'ro',
  isa     => HashRef,
  default => sub { {} }
);

=attr ssl_opts

Passed on to L<LWP::UserAgent> after the options above, for what they do
not cover.

=cut

has timeout => (
  is      => 'ro',
  isa     => Int,
  default => 60
);

=attr timeout

Seconds to wait for an answer, 60 by default. An iDRAC is slow. It is also
the time the SSH connection and each racadm command are given.

=cut

has ssh => (
  is      => 'ro',
  isa     => Bool,
  default => 1
);

=attr ssh

True by default. False says racadm is not to be used: BIOS, jobs and virtual
media are L<WWW::iDRAC::Error::Unsupported> without any connection being
made, and the license is not read.

=cut

has ssh_username => ( is => 'ro', isa => Maybe [Str] );
has ssh_password => ( is => 'ro', isa => Maybe [Str] );

=attr ssh_username

=attr ssh_password

For the SSH login, when it is not the one of L</username> and L</password>.
Give both or neither: one without the other is
L<WWW::iDRAC::Error::Validation>.

=cut

has ssh_port => ( is => 'ro', isa => Int, default => 22 );

=attr ssh_port

The port of the SSH service, 22 by default. The port in L</host> is the HTTPS
one and is not used for SSH.

=cut

has ssh_known_hosts     => ( is => 'ro', isa => Str, predicate => 'has_ssh_known_hosts' );
has ssh_host_key        => ( is => 'ro', isa => Str, predicate => 'has_ssh_host_key' );
has ssh_verify_host_key => ( is => 'ro', isa => Bool, default => 1 );
has ssh_opts            => ( is => 'ro', isa => ArrayRef [Str], default => sub { [] } );

=attr ssh_known_hosts

A C<known_hosts> file to check the SSH host key against. It is the only file
looked at: the global C<known_hosts> of the machine is ignored. Without this
and without L</ssh_host_key> the default files of the SSH client are used.
Not allowed together with L</ssh_host_key>.

=attr ssh_host_key

The host key to expect: the type and the base64 key, like C<ssh-ed25519
AAAA...>, as C<ssh-keyscan -t ed25519 HOST> prints it without the name. Not
allowed together with L</ssh_known_hosts>.

=attr ssh_verify_host_key

True by default. False accepts any host key. Not allowed together with
L</ssh_known_hosts> or L</ssh_host_key>.

=attr ssh_opts

Further C<Name=value> options for the SSH client, for a controller that
needs an algorithm a current OpenSSH has switched off. They cannot override
the options the dist fixes (host key checking, the login methods, one
password attempt, see L<WWW::iDRAC::Racadm::SSH/options_from>). An entry that
is not C<Name=value> without spaces is L<WWW::iDRAC::Error::Validation>, thrown
when the connection is made.

=cut

has ua => (
  is  => 'lazy',
  isa => InstanceOf ['LWP::UserAgent']
);

sub _build_ua {
  my ( $self ) = @_;
  my %ssl = $self->verify_ssl ? ( verify_hostname => 1 ) : ( verify_hostname => 0, SSL_verify_mode => 0 );
  $ssl{SSL_ca_file}     = $self->ssl_ca_file     if $self->has_ssl_ca_file;
  $ssl{SSL_fingerprint} = $self->ssl_fingerprint if $self->has_ssl_fingerprint;
  return LWP::UserAgent->new(
    agent      => 'WWW-iDRAC/'.$VERSION,
    timeout    => $self->timeout,
    keep_alive => 1,
    # a redirect would carry the session token or the password to wherever it leads
    max_redirect => 0,
    ssl_opts     => { %ssl, %{ $self->ssl_opts } }
  );
}

=attr ua

The L<LWP::UserAgent>. The one built here follows no redirect, because a
redirect would carry the session token or the password to wherever it leads.
Give your own and neither that nor the TLS attributes and L</timeout> above
are applied.

=cut

sub BUILD {
  my ( $self ) = @_;
  WWW::iDRAC::Error::Validation->throw(
    message => 'host is required'
  ) unless defined $self->host && length $self->host;
  WWW::iDRAC::Error::Validation->throw(
    message => 'host is a name or an address, optionally with :port'
  ) unless $self->host =~ /\A(?:\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9._-]+)(?::[0-9]+)?\z/;
  WWW::iDRAC::Error::Validation->throw(
    message => 'username is required'
  ) unless defined $self->username && length $self->username;
  WWW::iDRAC::Error::Validation->throw(
    message => 'password is required'
  ) unless defined $self->password && length $self->password;
  WWW::iDRAC::Error::Validation->throw(
    message => 'verify_ssl => 0 with ssl_fingerprint drops the pin: either verify the certificate or set a fingerprint, not both'
  ) if !$self->verify_ssl && $self->has_ssl_fingerprint;
  WWW::iDRAC::Error::Validation->throw(
    message => 'ssh_port is a port number'
  ) unless $self->ssh_port >= 1 && $self->ssh_port <= 65535;
  WWW::iDRAC::Error::Validation->throw(
    message => 'ssh_verify_host_key => 0 with ssh_known_hosts or ssh_host_key drops the check: either verify the host key or give it, not both'
  ) if !$self->ssh_verify_host_key && ( $self->has_ssh_known_hosts || $self->has_ssh_host_key );
  WWW::iDRAC::Error::Validation->throw(
    message => 'ssh_known_hosts and ssh_host_key are two ways to say the same thing: give one'
  ) if $self->has_ssh_known_hosts && $self->has_ssh_host_key;
  WWW::iDRAC::Error::Validation->throw(
    message => 'ssh_username and ssh_password go together'
  ) if defined $self->ssh_username xor defined $self->ssh_password;
  return;
}

sub base_url { 'https://'.$_[0]->host }

=method base_url

C<https://> and L</host>.

=cut

has redfish => ( is => 'lazy' );

sub _build_redfish {
  my ( $self ) = @_;
  return WWW::iDRAC::Redfish->new(
    base_url => $self->base_url,
    username => $self->username,
    password => $self->password,
    session  => $self->session,
    ua       => $self->ua
  );
}

=attr redfish

The L<WWW::iDRAC::Redfish> transport. Also the way to everything the facade
does not cover.

=cut

has racadm => ( is => 'lazy', isa => Object, predicate => 'has_racadm' );

sub _build_racadm {
  my ( $self ) = @_;
  # the HTTPS port in host is not the SSH port
  my $host = $self->host;
  $host =~ s/\A\[([0-9A-Fa-f:.]+)\](?::[0-9]+)?\z/$1/ or $host =~ s/:[0-9]+\z//;
  return WWW::iDRAC::Racadm->new(
    host            => $host,
    port            => $self->ssh_port,
    username        => $self->ssh_username // $self->username,
    password        => $self->ssh_password // $self->password,
    timeout         => $self->timeout,
    enabled         => $self->ssh,
    verify_host_key => $self->ssh_verify_host_key,
    ssh_opts        => $self->ssh_opts,
    ( $self->has_ssh_known_hosts ? ( known_hosts => $self->ssh_known_hosts ) : () ),
    ( $self->has_ssh_host_key    ? ( host_key    => $self->ssh_host_key )    : () )
  );
}

=attr racadm

The L<WWW::iDRAC::Racadm> transport: the way to what Redfish lacks on an
iDRAC 7 or 8, and to the text racadm prints. Not connected until a command is
sent. May be given to the constructor, for a transport of your own.

=cut

has system => ( is => 'lazy' );

sub _build_system { WWW::iDRAC::System->new( redfish => $_[0]->redfish ) }

=attr system

L<WWW::iDRAC::System>: inventory and state of the server.

=cut

has power => ( is => 'lazy' );

sub _build_power { WWW::iDRAC::Power->new( redfish => $_[0]->redfish ) }

=attr power

L<WWW::iDRAC::Power>: switching the server, and what it draws.

=cut

has sensors => ( is => 'lazy' );

sub _build_sensors { WWW::iDRAC::Sensors->new( redfish => $_[0]->redfish ) }

=attr sensors

L<WWW::iDRAC::Sensors>: temperatures, fans, voltages, power supplies.

=cut

has logs => ( is => 'lazy' );

sub _build_logs { WWW::iDRAC::Logs->new( redfish => $_[0]->redfish ) }

=attr logs

L<WWW::iDRAC::Logs>: the system event log and the lifecycle log.

=cut

has manager => ( is => 'lazy' );

sub _build_manager { WWW::iDRAC::Manager->new( redfish => $_[0]->redfish ) }

=attr manager

L<WWW::iDRAC::Manager>: the iDRAC itself.

=cut

has bios => ( is => 'lazy' );

sub _build_bios { WWW::iDRAC::Bios->new( racadm => $_[0]->racadm ) }

=attr bios

L<WWW::iDRAC::Bios>: BIOS attributes, read and staged, over racadm.

=cut

has jobs => ( is => 'lazy' );

sub _build_jobs { WWW::iDRAC::Jobs->new( racadm => $_[0]->racadm ) }

=attr jobs

L<WWW::iDRAC::Jobs>: the job queue, over racadm.

=cut

has virtual_media => ( is => 'lazy' );

sub _build_virtual_media { WWW::iDRAC::VirtualMedia->new( racadm => $_[0]->racadm ) }

=attr virtual_media

L<WWW::iDRAC::VirtualMedia>: a remote image attached to the server, over
racadm.

=cut

has capabilities => ( is => 'lazy' );

sub _build_capabilities {
  my ( $self ) = @_;
  return WWW::iDRAC::Capabilities->new(
    redfish => $self->redfish,
    racadm  => $self->racadm,
    areas   => { map { $_ => $self->$_ } qw( system power sensors logs manager bios jobs virtual_media ) }
  );
}

=attr capabilities

L<WWW::iDRAC::Capabilities>: what this controller is and what it can do.

=cut

sub logout {
  my ( $self ) = @_;
  my $redfish = $self->redfish->logout;
  my $racadm  = $self->has_racadm ? $self->racadm->logout : 0;
  return $redfish || $racadm ? 1 : 0;
}

=method logout

Ends the Redfish session and closes the SSH connection, whichever there is,
and returns true when there was one. An iDRAC allows only a few of each at a
time, so call this when you are done. They are also ended when the last
object using them goes away, but do not rely on that at the very end of a
program.

=cut

1;
