package WWW::iDRAC::System;

# ABSTRACT: Inventory and state of the server behind an iDRAC

use Moo;
use WWW::iDRAC::Util qw( health_of number state_of text );
use namespace::autoclean;

our $VERSION = '0.001';

sub area { 'system' }

with 'WWW::iDRAC::Role::Capability';

=synopsis

    my $info = $idrac->system->info;
    print $info->{model}, ' ', $info->{service_tag}, "\n";

    print $_->{name}, ': ', $_->{size_mib}, "\n" for @{ $idrac->system->memory };

=description

What the server is made of. Every method returns hashes with the keys named
below; a key the controller has nothing for is there and C<undef>.

=cut

sub info {
  my ( $self ) = @_;
  return $self->info_from( $self->resource( Systems => 'info' ) );
}

sub info_from {
  my ( $class, $doc ) = @_;
  my $cpu    = ref $doc->{ProcessorSummary} eq 'HASH' ? $doc->{ProcessorSummary} : {};
  my $memory = ref $doc->{MemorySummary} eq 'HASH'    ? $doc->{MemorySummary}    : {};
  return {
    manufacturer => text( $doc->{Manufacturer} ),
    model        => text( $doc->{Model} ),
    service_tag  => text( $doc->{SKU} ),
    serial       => text( $doc->{SerialNumber} ),
    uuid         => text( $doc->{UUID} ),
    asset_tag    => text( $doc->{AssetTag} ),
    hostname     => text( $doc->{HostName} ),
    bios_version => text( $doc->{BiosVersion} ),
    power_state  => state_of( $doc->{PowerState} ),
    health       => health_of( $doc->{Status} ),
    cpu_count    => number( $cpu->{Count} ),
    cpu_model    => text( $cpu->{Model} ),
    memory_gib   => number( $memory->{TotalSystemMemoryGiB} )
  };
}

=method info

C<manufacturer>, C<model>, C<service_tag>, C<serial>, C<uuid>, C<asset_tag>,
C<hostname>, C<bios_version>, C<power_state>, C<health>, C<cpu_count>,
C<cpu_model>, C<memory_gib>.

=method info_from

    my $info = WWW::iDRAC::System->info_from($system_document);

The translation behind L</info>, without I/O. The same exists for the other
methods as L</processor_from>, L</memory_from> and L</nic_from>.

=cut

sub _parts {
  my ( $self, $key, $method ) = @_;
  my $path = $self->linked_path( $self->resource( Systems => $method ), $key, $method );
  return $self->fetch_members( $path, $method );
}

sub processors {
  my ( $self ) = @_;
  return [ map { $self->processor_from($_) } $self->_parts( Processors => 'processors' ) ];
}

sub processor_from {
  my ( $class, $doc ) = @_;
  return {
    name      => text( $doc->{Socket} ) // text( $doc->{Name} ) // text( $doc->{Id} ),
    model     => text( $doc->{Model} ),
    cores     => number( $doc->{TotalCores} ),
    threads   => number( $doc->{TotalThreads} ),
    speed_mhz => number( $doc->{MaxSpeedMHz} ),
    health    => health_of( $doc->{Status} )
  };
}

=method processors

One hash per processor: C<name>, C<model>, C<cores>, C<threads>,
C<speed_mhz>, C<health>.

=method processor_from

=cut

sub memory {
  my ( $self ) = @_;
  return [ map { $self->memory_from($_) } $self->_parts( Memory => 'memory' ) ];
}

sub memory_from {
  my ( $class, $doc ) = @_;
  return {
    name         => text( $doc->{DeviceLocator} ) // text( $doc->{Name} ) // text( $doc->{Id} ),
    size_mib     => number( $doc->{CapacityMiB} ),
    type         => text( $doc->{MemoryDeviceType} ),
    speed_mhz    => number( $doc->{OperatingSpeedMhz} ),
    manufacturer => text( $doc->{Manufacturer} ),
    part_number  => text( $doc->{PartNumber} ),
    serial       => text( $doc->{SerialNumber} ),
    health       => health_of( $doc->{Status} )
  };
}

=method memory

One hash per memory module: C<name>, C<size_mib>, C<type>, C<speed_mhz>,
C<manufacturer>, C<part_number>, C<serial>, C<health>.

=method memory_from

=cut

sub nics {
  my ( $self ) = @_;
  return [ map { $self->nic_from($_) } $self->_parts( EthernetInterfaces => 'nics' ) ];
}

sub nic_from {
  my ( $class, $doc ) = @_;
  my $link = text( $doc->{LinkStatus} );
  return {
    name       => text( $doc->{Id} ) // text( $doc->{Name} ),
    mac        => text( $doc->{MACAddress} ) // text( $doc->{PermanentMACAddress} ),
    speed_mbps => number( $doc->{SpeedMbps} ),
    link_up    => defined $link ? ( $link eq 'LinkUp' ? 1 : 0 ) : undef,
    health     => health_of( $doc->{Status} )
  };
}

=method nics

One hash per network interface of the server: C<name>, C<mac>,
C<speed_mbps>, C<link_up>, C<health>.

=method nic_from

=cut

sub probe_info       { $_[0]->resource( Systems => 'info' ) }
sub probe_processors { $_[0]->linked_path( $_[0]->resource( Systems => 'processors' ), Processors => 'processors' ) }
sub probe_memory     { $_[0]->linked_path( $_[0]->resource( Systems => 'memory' ), Memory => 'memory' ) }
sub probe_nics       { $_[0]->linked_path( $_[0]->resource( Systems => 'nics' ), EthernetInterfaces => 'nics' ) }

=method probe_info

=method probe_processors

=method probe_memory

=method probe_nics

What L<WWW::iDRAC::Role::Capability/supports> asks.

=cut

1;
