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
C<host_key> (the host key is unknown or has changed), C<auth> (the login was
refused), C<timeout> or C<other>. C<undef> for a failure over HTTP.

=cut

1;
