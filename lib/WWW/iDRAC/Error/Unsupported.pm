package WWW::iDRAC::Error::Unsupported;

# ABSTRACT: Raised when this iDRAC does not have what was asked for

use Moo;
extends 'WWW::iDRAC::Error';

our $VERSION = '0.001';

=description

Thrown by the capability classes, before anything is sent, when the
controller does not offer the resource or the action a method needs. What a
controller offers depends on its generation, its firmware and its license.

=cut

has capability => (
  is       => 'ro',
  required => 1
);

=attr capability

The name of the method that cannot be served, as C<area.method>, for example
C<power.cycle>. The same names go into
L<WWW::iDRAC::Capabilities/supports>.

=cut

has reason => ( is => 'ro' );

=attr reason

What exactly is missing.

=cut

1;
