package WWW::iDRAC::Error::API;

# ABSTRACT: Raised when the iDRAC answers with an HTTP error

use Moo;
extends 'WWW::iDRAC::Error';

our $VERSION = '0.001';

=description

Redfish reports an error as C<< {"error": {"code", "message",
"@Message.ExtendedInfo": [...]}} >>. The first entry of the extended
information is what Dell fills with the useful part, and it ends up in
L</message_id>, L</api_message> and L</resolution>.

=cut

has http_status => (
  is       => 'ro',
  required => 1
);

=attr http_status

The HTTP status code as a number, for example 404.

=cut

has message_id => ( is => 'ro' );

=attr message_id

Dell's identifier of the message, for example C<IDRAC.1.6.SYS403>, when the
iDRAC sent one.

=cut

has api_message => ( is => 'ro' );

=attr api_message

What the iDRAC said, if it said anything.

=cut

has resolution => ( is => 'ro' );

=attr resolution

What Dell suggests doing about it, if the iDRAC sent a suggestion.

=cut

sub is_not_found    { $_[0]->http_status == 404 ? 1 : 0 }
sub is_unauthorized { $_[0]->http_status == 401 ? 1 : 0 }

=method is_not_found

=method is_unauthorized

True for status 404 and 401.

=cut

1;
