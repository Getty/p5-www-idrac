package WWW::iDRAC::Sensors;

# ABSTRACT: Temperatures, fans, voltages and power supplies of a server

use Moo;
use WWW::iDRAC::Util qw( health_of list_of number text );
use namespace::autoclean;

our $VERSION = '0.001';

sub area { 'sensors' }

with 'WWW::iDRAC::Role::Capability';

=synopsis

    for my $t ( @{ $idrac->sensors->temperatures } ) {
      next unless defined $t->{celsius};
      print $t->{name}, ': ', $t->{celsius}, "\n";
    }

=description

What the chassis measures. A sensor the controller lists without a reading,
an empty socket for example, is listed here too, with the reading C<undef>.

=cut

sub _document {
  my ( $self, $key, $method ) = @_;
  return $self->fetch( $self->linked_path( $self->resource( Chassis => $method ), $key, $method ), $method );
}

sub temperatures {
  my ( $self ) = @_;
  return [ map { $self->temperature_from($_) } list_of( $self->_document( Thermal => 'temperatures' )->{Temperatures} ) ];
}

sub temperature_from {
  my ( $class, $doc ) = @_;
  return {
    name           => text( $doc->{Name} ),
    celsius        => number( $doc->{ReadingCelsius} ),
    upper_warning  => number( $doc->{UpperThresholdNonCritical} ),
    upper_critical => number( $doc->{UpperThresholdCritical} ),
    lower_warning  => number( $doc->{LowerThresholdNonCritical} ),
    lower_critical => number( $doc->{LowerThresholdCritical} ),
    health         => health_of( $doc->{Status} )
  };
}

=method temperatures

One hash per sensor: C<name>, C<celsius>, C<upper_warning>,
C<upper_critical>, C<lower_warning>, C<lower_critical>, C<health>.

=method temperature_from

    my $t = WWW::iDRAC::Sensors->temperature_from($entry);

The translation of one entry, without I/O. The same exists as L</fan_from>,
L</voltage_from> and L</power_supply_from>.

=cut

sub fans {
  my ( $self ) = @_;
  return [ map { $self->fan_from($_) } list_of( $self->_document( Thermal => 'fans' )->{Fans} ) ];
}

sub fan_from {
  my ( $class, $doc ) = @_;
  return {
    name    => text( $doc->{FanName} ) // text( $doc->{Name} ),
    reading => number( $doc->{Reading} ),
    units   => text( $doc->{ReadingUnits} ),
    health  => health_of( $doc->{Status} )
  };
}

=method fans

One hash per fan: C<name>, C<reading>, C<units> (C<RPM> or C<Percent>),
C<health>.

=method fan_from

=cut

sub voltages {
  my ( $self ) = @_;
  return [ map { $self->voltage_from($_) } list_of( $self->_document( Power => 'voltages' )->{Voltages} ) ];
}

sub voltage_from {
  my ( $class, $doc ) = @_;
  return {
    name   => text( $doc->{Name} ),
    volts  => number( $doc->{ReadingVolts} ),
    health => health_of( $doc->{Status} )
  };
}

=method voltages

One hash per voltage sensor: C<name>, C<volts>, C<health>.

=method voltage_from

=cut

sub power_supplies {
  my ( $self ) = @_;
  return [ map { $self->power_supply_from($_) } list_of( $self->_document( Power => 'power_supplies' )->{PowerSupplies} ) ];
}

sub power_supply_from {
  my ( $class, $doc ) = @_;
  return {
    name           => text( $doc->{Name} ),
    model          => text( $doc->{Model} ),
    serial         => text( $doc->{SerialNumber} ),
    firmware       => text( $doc->{FirmwareVersion} ),
    capacity_watts => number( $doc->{PowerCapacityWatts} ),
    input_volts    => number( $doc->{LineInputVoltage} ),
    output_watts   => number( $doc->{LastPowerOutputWatts} ) // number( $doc->{PowerOutputWatts} ),
    health         => health_of( $doc->{Status} )
  };
}

=method power_supplies

One hash per power supply: C<name>, C<model>, C<serial>, C<firmware>,
C<capacity_watts>, C<input_volts>, C<output_watts>, C<health>.

=method power_supply_from

=cut

sub probe_temperatures   { $_[0]->linked_path( $_[0]->resource( Chassis => 'temperatures' ),   Thermal => 'temperatures' ) }
sub probe_fans           { $_[0]->linked_path( $_[0]->resource( Chassis => 'fans' ),           Thermal => 'fans' ) }
sub probe_voltages       { $_[0]->linked_path( $_[0]->resource( Chassis => 'voltages' ),       Power   => 'voltages' ) }
sub probe_power_supplies { $_[0]->linked_path( $_[0]->resource( Chassis => 'power_supplies' ), Power   => 'power_supplies' ) }

=method probe_temperatures

=method probe_fans

=method probe_voltages

=method probe_power_supplies

What L<WWW::iDRAC::Role::Capability/supports> asks.

=cut

1;
