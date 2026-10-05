package WWW::iDRAC::Role::HTTP;

# ABSTRACT: Sending requests to an iDRAC and turning failures into exceptions

use HTTP::Request;
use JSON::MaybeXS;
use MIME::Base64 qw( encode_base64 );
use WWW::iDRAC::Error::API;
use WWW::iDRAC::Error::Network;
use Moo::Role;

our $VERSION = '0.001';

requires 'ua';

=description

One L<LWP::UserAgent>, JSON in and out, and the mapping of Redfish's error
document onto L<WWW::iDRAC::Error::API>. L</build_request> and
L</read_response> do no I/O, so an asynchronous client can use them as they
are and replace only L</send_request>.

=cut

sub json_codec { JSON::MaybeXS->new( utf8 => 1, canonical => 1 ) }

sub api_error_class     { 'WWW::iDRAC::Error::API' }
sub network_error_class { 'WWW::iDRAC::Error::Network' }

=method json_codec

The JSON encoder and decoder.

=method api_error_class

=method network_error_class

The classes the errors are thrown as. An asynchronous client overrides them
with its own subclasses.

=cut

sub build_request {
  my ( $self, $method, $url, %arg ) = @_;
  my $request = HTTP::Request->new( $method => $url );
  $request->header( Accept => 'application/json' );
  $request->header( 'X-Auth-Token' => $arg{token} ) if defined $arg{token};
  if ( $arg{basic} ) {
    # credentials are characters, as they are for the JSON body of a session login
    my $pair = join ':', @{ $arg{basic} };
    utf8::encode($pair);
    $request->header( Authorization => 'Basic '.encode_base64( $pair, '' ) );
  }
  if ( exists $arg{json} ) {
    $request->header( 'Content-Type' => 'application/json' );
    $request->content( $self->json_codec->encode( $arg{json} ) );
  }
  return $request;
}

=method build_request

    my $request = $self->build_request( POST => $url, json => \%body, token => $token );
    my $request = $self->build_request( GET => $url, basic => [ $username, $password ] );

The L<HTTP::Request> for one call: JSON accepted, the session token or the
Basic credentials when given, the body as JSON.

=cut

sub extended_info {
  my ( $self, $data ) = @_;
  return {} unless ref $data eq 'HASH';
  my $error = ref $data->{error} eq 'HASH' ? $data->{error} : $data;
  my $list  = $error->{'@Message.ExtendedInfo'};
  my ( $first ) = grep { ref $_ eq 'HASH' } ref $list eq 'ARRAY' ? @$list : ();
  return {
    message_id => $first ? $first->{MessageId} : $error->{code},
    message    => ( $first ? $first->{Message} : undef ) // $error->{message},
    resolution => $first ? $first->{Resolution} : undef
  };
}

=method extended_info

    my $info = $self->extended_info($data);

C<message_id>, C<message> and C<resolution> out of a Redfish error document:
the first entry of C<@Message.ExtendedInfo> when there is one, the plain
C<code> and C<message> otherwise.

=cut

sub read_response {
  my ( $self, $response, $method, $url ) = @_;
  # decoded_content undoes a Content-Encoding, the raw content does not; with
  # charset => 'none' the bytes stay bytes, which the JSON codec decodes itself
  my $content = $response->decoded_content( charset => 'none' ) // '';
  my $data    = length $content ? eval { $self->json_codec->decode($content) } : undef;
  return {
    status   => $response->code,
    data     => $data,
    location => scalar $response->header('Location'),
    token    => scalar $response->header('X-Auth-Token')
  } if $response->is_success;
  my $info = $self->extended_info($data);
  $self->api_error_class->throw(
    message     => $method.' '.$url.' failed: '.$response->status_line.( defined $info->{message} ? ' - '.$info->{message} : '' ),
    http_status => $response->code,
    message_id  => $info->{message_id},
    api_message => $info->{message},
    resolution  => $info->{resolution}
  );
}

=method read_response

    my $result = $self->read_response( $response, $method, $url );

Turns an L<HTTP::Response> into C<status>, the decoded C<data>, the
C<location> header and the C<token> from C<X-Auth-Token>, or throws
L</api_error_class> for any status that is not a success.

=cut

sub send_request {
  my ( $self, $method, $url, %arg ) = @_;
  my $response = $self->ua->request( $self->build_request( $method, $url, %arg ) );
  $self->network_error_class->throw( message => $method.' '.$url.': '.$response->status_line )
    if $response->code == 500 && ( $response->header('Client-Warning') // '' ) eq 'Internal response';
  return $self->read_response( $response, $method, $url );
}

=method send_request

    my $result = $self->send_request( POST => $url, json => \%body, token => $token );

Sends one request. Throws L<WWW::iDRAC::Error::Network> when no answer came
back, a refused certificate included, and L<WWW::iDRAC::Error::API> for an
error status. Neither message contains the password.

=cut

1;
