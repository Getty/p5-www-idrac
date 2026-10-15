package WWW::iDRAC::Error::Network;

# ABSTRACT: Raised when the iDRAC could not be reached, TLS and SSH failures included

use Moo;
extends 'WWW::iDRAC::Error';

our $VERSION = '0.001';

=description

No answer arrived: the connection failed, the certificate or the host key was
refused, the login was refused, or the controller did not answer in time.

=cut

has cause => ( is => 'ro' );

=attr cause

For a failure over SSH, one of C<refused> (nothing listens on the port),
C<unreachable> (no route, network unreachable, no name resolution, or the
connection attempt timed out), C<host_key> (the host key is unknown or has
changed), C<auth> (the login was refused), C<timeout> (a command ran out of
time) or C<other>. The cause is worked out from what the SSH client printed,
see L<WWW::iDRAC::Racadm/run>. C<undef> for a failure over HTTP.

=cut

1;
