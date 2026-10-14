package WWW::iDRAC::Role::Racadm;

# ABSTRACT: What the capability classes served over racadm share

use Scalar::Util qw( blessed );
use WWW::iDRAC::Error::Unsupported;
use Moo::Role;

our $VERSION = '0.001';

with 'WWW::iDRAC::Role::Area';

=description

The racadm counterpart of L<WWW::iDRAC::Role::Capability>: a capability
class with this role reaches the controller only through L</racadm>, returns
translated data, never the text racadm printed, and turns what this
controller cannot do into L<WWW::iDRAC::Error::Unsupported> before it sends
anything it cannot take back.

Three things are a controller's fact and not an error, and become
C<Unsupported> with the reason: racadm is switched off in the facade
(C<< ssh => 0 >>), nothing listens on the SSH port of the controller, and a
license the command needs is missing (C<SWC0242>, measured on an iDRAC 8
with an Express license for virtual media). A refused login, a changed host
key and a timeout are not facts about the controller but about the way to
it, and stay L<WWW::iDRAC::Error::Network>.

=cut

has racadm => (
  is       => 'ro',
  required => 1
);

=attr racadm

Required. The L<WWW::iDRAC::Racadm> transport.

=cut

sub racadm_run {
  my ( $self, $method, @word ) = @_;
  $self->unsupported( $method, 'racadm over SSH is switched off (ssh => 0)' ) unless $self->racadm->enabled;
  my $text;
  return $text if eval { $text = $self->racadm->run(@word); 1 };
  my $error = $@;
  if ( blessed $error && $error->isa('WWW::iDRAC::Error::API') && ( $error->message_id // '' ) eq 'SWC0242' ) {
    $self->unsupported( $method, 'the controller has no license for it ('.( $error->resolution // 'a required license is missing' ).')' );
  }
  if ( blessed $error && $error->isa('WWW::iDRAC::Error::Network') && ( $error->cause // '' ) eq 'refused' ) {
    $self->unsupported( $method, 'nothing answers on the SSH port of the controller, which racadm needs; SSH may be switched off on the iDRAC' );
  }
  die $error;
}

=method racadm_run

    my $text = $self->racadm_run( group => get => 'BIOS.BiosBootSettings' );

Sends one racadm command, the words after the method name, on behalf of the
named method of this area and returns what racadm printed. The controller-side facts above are
L<WWW::iDRAC::Error::Unsupported> for that method; every other error is
thrown as L<WWW::iDRAC::Racadm/run> throws it.

=cut

1;
