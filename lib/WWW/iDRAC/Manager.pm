package WWW::iDRAC::Manager;

# ABSTRACT: The iDRAC itself - what it is, how it is reached, restarting it

use Moo;
use WWW::iDRAC::Util qw( health_of list_of text );
use namespace::autoclean;

our $VERSION = '0.001';

sub area { 'manager' }

with 'WWW::iDRAC::Role::Capability';

=synopsis

    print $idrac->manager->info->{firmware}, "\n";
    print join( ', ', @{ $idrac->manager->network->{ipv4} } ), "\n";

    $idrac->manager->restart;      # the controller, not the server

=cut

sub info {
  my ( $self ) = @_;
  return $self->info_from( $self->resource( Managers => 'info' ) );
}

sub info_from {
  my ( $class, $doc ) = @_;
  return {
    model     => text( $doc->{Model} ),
    firmware  => text( $doc->{FirmwareVersion} ),
    health    => health_of( $doc->{Status} ),
    date_time => text( $doc->{DateTime} ),
    uuid      => text( $doc->{UUID} )
  };
}

=method info

C<model>, C<firmware>, C<health>, C<date_time> as the controller's own clock
reads, C<uuid>.

=method info_from

    my $info = WWW::iDRAC::Manager->info_from($manager_document);

The translation behind L</info>, without I/O.

=cut

sub _interface {
  my ( $self ) = @_;
  my $path = $self->linked_path( $self->resource( Managers => 'network' ), EthernetInterfaces => 'network' );
  my ( $interface ) = $self->fetch_members( $path, 'network', limit => 1 );
  return $interface // $self->unsupported( network => 'the controller lists no network interface' );
}

sub network {
  my ( $self ) = @_;
  return $self->network_from( $self->_interface );
}

sub network_from {
  my ( $class, $doc ) = @_;
  my $addresses = sub { [ grep { defined } map { text( $_->{Address} ) } list_of( $_[0] ) ] };
  # an unset address comes as all zeroes; leave those out
  my $set = sub { [ grep { $_ ne '0.0.0.0' && $_ ne '::' } @{ $_[0] } ] };
  return {
    hostname => text( $doc->{HostName} ),
    fqdn     => text( $doc->{FQDN} ),
    mac      => text( $doc->{MACAddress} ) // text( $doc->{PermanentMACAddress} ),
    ipv4     => $set->( $addresses->( $doc->{IPv4Addresses} ) ),
    ipv6     => $set->( $addresses->( $doc->{IPv6Addresses} ) ),
    dns      => $set->( [ grep { defined } map { text($_) } ref $doc->{NameServers} eq 'ARRAY' ? @{ $doc->{NameServers} } : () ] )
  };
}

=method network

How the controller is reached: C<hostname>, C<fqdn>, C<mac>, and the lists
C<ipv4>, C<ipv6> and C<dns> of addresses. Addresses that are not set are
left out.

=method network_from

    my $network = WWW::iDRAC::Manager->network_from($interface_document);

The translation behind L</network>, without I/O.

=cut

sub reset_action {
  my ( $self ) = @_;
  my $doc    = $self->resource( Managers => 'restart' );
  my $action = ref $doc->{Actions} eq 'HASH' ? $doc->{Actions}{'#Manager.Reset'} : undef;
  $self->unsupported( restart => 'the manager offers no reset action' ) unless ref $action eq 'HASH' && defined $action->{target};
  my $allowed = $action->{'ResetType@Redfish.AllowableValues'};
  $self->unsupported( restart => 'reset type GracefulRestart is not offered, only '.join( ', ', grep { defined } @$allowed ) )
    if ref $allowed eq 'ARRAY' && !grep { defined && $_ eq 'GracefulRestart' } @$allowed;
  return $action->{target};
}

sub restart {
  my ( $self ) = @_;
  $self->redfish->post( $self->reset_action, { ResetType => 'GracefulRestart' } );
  # the controller forgets its sessions when it restarts
  $self->redfish->forget_session;
  return 1;
}

=method restart

Restarts the iDRAC. The server keeps running. The controller is away for a
few minutes afterwards, and requests in that time end in
L<WWW::iDRAC::Error::Network>.

=method reset_action

Where L</restart> sends its order, or L<WWW::iDRAC::Error::Unsupported>.

=cut

sub probe_info    { $_[0]->resource( Managers => 'info' ) }
sub probe_network { $_[0]->_interface }
sub probe_restart { $_[0]->reset_action }

=method probe_info

=method probe_network

=method probe_restart

What L<WWW::iDRAC::Role::Area/supports> asks.

=cut

1;
