package WWW::iDRAC::Role::Area;

# ABSTRACT: What every capability class of WWW::iDRAC shares, whatever transport serves it

use Scalar::Util qw( blessed );
use WWW::iDRAC::Error::Unsupported;
use WWW::iDRAC::Error::Validation;
use Moo::Role;

our $VERSION = '0.001';

requires 'area';

=description

A capability class answers for one area and says, for each of its public
methods C<x>, whether this controller can serve it: the method C<probe_x>
beside it does what the method would do up to the point of changing anything
and throws L<WWW::iDRAC::Error::Unsupported> where the method would.
L</supports> is built on those probes.

The role does not care which transport a class is served over.
L<WWW::iDRAC::Role::Capability> adds Redfish to it,
L<WWW::iDRAC::Role::Racadm> adds racadm over SSH.

=cut

sub unsupported {
  my ( $self, $method, $reason ) = @_;
  my $capability = $self->area.'.'.$method;
  WWW::iDRAC::Error::Unsupported->throw(
    message    => $capability.' is not available on this iDRAC: '.$reason,
    capability => $capability,
    reason     => $reason
  );
}

=method unsupported

    $self->unsupported( cycle => 'reset type PowerCycle is not offered' );

Throws L<WWW::iDRAC::Error::Unsupported> for a method of this area.

=cut

sub supports {
  my ( $self, $method ) = @_;
  my $probe = defined $method && $method =~ /\A[a-z_]+\z/ ? $self->can( 'probe_'.$method ) : undef;
  WWW::iDRAC::Error::Validation->throw( message => 'unknown capability '.$self->area.'.'.( $method // '' ) ) unless $probe;
  return 1 if eval { $self->$probe; 1 };
  my $error = $@;
  return 0 if blessed $error && $error->isa('WWW::iDRAC::Error::Unsupported');
  die $error;
}

=method supports

    if ( $idrac->power->supports('cycle') ) { ... }

True when the method of that name can be served by this controller. A name
that is no method of the area is a L<WWW::iDRAC::Error::Validation>; an error
on the way to the answer is thrown as it is.

=cut

1;
