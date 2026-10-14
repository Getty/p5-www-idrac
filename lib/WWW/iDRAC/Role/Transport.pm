package WWW::iDRAC::Role::Transport;

# ABSTRACT: What the transports of WWW::iDRAC have in common

use Moo::Role;

our $VERSION = '0.001';

requires 'transport_name';
requires 'logout';

=description

WWW::iDRAC reaches a controller over two transports: L<WWW::iDRAC::Redfish>
over HTTPS and L<WWW::iDRAC::Racadm> over SSH. What the facade needs of both
is small, and this role says it:

=over

=item C<transport_name>

C<redfish> or C<racadm>. Used in messages and by the facade to say which
transport a capability class is served over.

=item C<logout>

Ends whatever the transport holds open on the controller (a Redfish session,
an SSH connection) and returns true when there was something to end. It must
be safe to call twice and from C<DEMOLISH>. A controller allows only a few
sessions of either kind, and frees an abandoned one only after a timeout.

=back

The roles of the capability classes build on it: a class that is served over
Redfish holds a C<redfish> transport, one that is served over racadm holds a
C<racadm> transport. Neither knows the other.

=cut

1;
