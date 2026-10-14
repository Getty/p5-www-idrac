package WWW::iDRAC::Error::API;

# ABSTRACT: Raised when the iDRAC answers with an HTTP error

use Moo;
extends 'WWW::iDRAC::Error';

our $VERSION = '0.001';

=description

Raised for an HTTP answer with an error status, and for an error that racadm
printed (see L<WWW::iDRAC::Racadm>), which has no HTTP status.

Redfish reports an error as C<< {"error": {"code", "message",
"@Message.ExtendedInfo": [...]}} >>. The first entry of the extended
information is what Dell fills with the useful part, and it ends up in
L</message_id>, L</api_message> and L</resolution>.

=cut

has http_status => ( is => 'ro' );

=attr http_status

The HTTP status code as a number, for example 404. C<undef> for an error that
racadm printed, which comes over SSH and has no status.

=cut

has message_id => ( is => 'ro' );

=attr message_id

Dell's identifier of the message, for example C<IDRAC.1.6.SYS403> from
Redfish or C<RAC1019> from racadm, when the iDRAC sent one.

=cut

has api_message => ( is => 'ro' );

=attr api_message

What the iDRAC said, if it said anything.

=cut

has resolution => ( is => 'ro' );

=attr resolution

What Dell suggests doing about it, if the iDRAC sent a suggestion.

=cut

# what racadm says when the object, the group or the job asked for is not there
my %RACADM_NOT_FOUND = map { $_ => 1 } qw( RAC992 RAC1019 RAC1020 );

sub is_not_found {
  my ( $self ) = @_;
  return $self->http_status == 404 ? 1 : 0 if defined $self->http_status;
  return defined $self->message_id && $RACADM_NOT_FOUND{ $self->message_id } ? 1 : 0;
}

sub is_unauthorized { defined $_[0]->http_status && $_[0]->http_status == 401 ? 1 : 0 }

=method is_not_found

True for status 404, and for the racadm errors that say the object, the
group or the job asked for does not exist (C<RAC992>, C<RAC1019>,
C<RAC1020>).

=method is_unauthorized

True for status 401.

=cut

1;
