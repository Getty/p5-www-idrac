package WWW::iDRAC;

# ABSTRACT: Perl client for Dell iDRAC - inventory, power, sensors and logs over Redfish

use Moo;
use LWP::UserAgent;
use Types::Standard qw( Bool HashRef InstanceOf Int Maybe Str );
use WWW::iDRAC::Capabilities;
use WWW::iDRAC::Error;
use WWW::iDRAC::Error::API;
use WWW::iDRAC::Error::Network;
use WWW::iDRAC::Error::Unsupported;
use WWW::iDRAC::Error::Validation;
use WWW::iDRAC::Logs;
use WWW::iDRAC::Manager;
use WWW::iDRAC::Power;
use WWW::iDRAC::Redfish;
use WWW::iDRAC::Sensors;
use WWW::iDRAC::System;
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

    # what the facade does not cover yet
    my $chassis = $idrac->redfish->get('/redfish/v1/Chassis');

    $idrac->logout;

=description

A client for the management controller of Dell PowerEdge servers. The
methods are cut by what you want to know or do, not by protocol: you ask for
C<< $idrac->system->info >> and do not care how the answer is fetched. In
this version everything is fetched over Redfish.

The methods return plain hashes with fixed keys, not Redfish documents. For
everything they do not cover there is L</redfish>, which hands out the raw
documents.

What a controller can do depends on its generation, its firmware and its
license. A method this controller cannot serve throws
L<WWW::iDRAC::Error::Unsupported> before anything is sent.

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

Seconds to wait for an answer, 60 by default. An iDRAC is slow.

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

has capabilities => ( is => 'lazy' );

sub _build_capabilities {
  my ( $self ) = @_;
  return WWW::iDRAC::Capabilities->new(
    redfish => $self->redfish,
    areas   => { map { $_ => $self->$_ } qw( system power sensors logs manager ) }
  );
}

=attr capabilities

L<WWW::iDRAC::Capabilities>: what this controller is and what it can do.

=cut

sub logout { $_[0]->redfish->logout }

=method logout

Ends the session. An iDRAC allows only a few at a time, so call this when
you are done. The session is also ended when the last object using it goes
away, but do not rely on that at the very end of a program.

=cut

1;
