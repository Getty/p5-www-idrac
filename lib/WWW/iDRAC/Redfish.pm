package WWW::iDRAC::Redfish;

# ABSTRACT: The Redfish transport of WWW::iDRAC, and the way to what the facade does not cover

use Moo;
use Scalar::Util qw( blessed );
use Types::Standard qw( Bool HashRef InstanceOf Maybe Str );
use WWW::iDRAC::Error::API;
use WWW::iDRAC::Error::Validation;
use namespace::autoclean;

our $VERSION = '0.001';

=synopsis

    my $redfish = $idrac->redfish;

    my $system = $redfish->get('/redfish/v1/Systems/System.Embedded.1');
    my @cpus   = $redfish->members( $system->{Processors}{'@odata.id'} );
    $redfish->post( $target, { ResetType => 'On' } );

=description

Everything L<WWW::iDRAC> does in phase 1 goes through this class. It logs in,
keeps the session token, logs in once more when the controller refuses the
token, and finds the system, the chassis and the manager without assuming
their names.

It is also the documented way out: what the facade does not cover yet is
reachable here, as raw Redfish documents. Nothing is translated on this
level, and a path that does not exist is a
L<WWW::iDRAC::Error::API> with C<is_not_found>.

=cut

has base_url => (
  is       => 'ro',
  isa      => Str,
  required => 1
);

=attr base_url

Required. C<https://host>, without a path.

=cut

has username => ( is => 'ro', isa => Str, required => 1 );
has password => ( is => 'ro', isa => Str, required => 1 );

=attr username

=attr password

Required.

=cut

has session => (
  is      => 'ro',
  isa     => Bool,
  default => 1
);

=attr session

True by default: log in once and send the session token. False sends the
credentials with every request as Basic authentication and creates no
session.

=cut

has ua => (
  is       => 'ro',
  isa      => InstanceOf ['LWP::UserAgent'],
  required => 1
);

=attr ua

Required. The L<LWP::UserAgent> all requests go through.

=cut

has _token        => ( is => 'rw', isa => Maybe [Str] );
has _session_path => ( is => 'rw', isa => Maybe [Str] );
has _root         => ( is => 'rw', isa => Maybe [HashRef] );
has _located      => ( is => 'ro', isa => HashRef, default => sub { {} } );

with 'WWW::iDRAC::Role::HTTP';

sub url {
  my ( $self, $path ) = @_;
  WWW::iDRAC::Error::Validation->throw( message => 'a Redfish path starts with a slash, got '.( $path // 'nothing' ) )
    unless defined $path && !ref $path && $path =~ m{\A/};
  return $self->base_url.$path;
}

=method url

    my $url = $redfish->url('/redfish/v1/');

The address of a path on this controller.

=cut

sub path_of {
  my ( $self, $address ) = @_;
  return undef unless defined $address && !ref $address && length $address;
  $address =~ s{\A[a-z][a-z0-9+.-]*://[^/]+}{}i;
  return $address;
}

=method path_of

    my $path = $redfish->path_of( $result->{location} );

The path of an address the controller handed out. Some firmware gives a full
URL where other firmware gives a path.

=cut

sub root {
  my ( $self ) = @_;
  return $self->_root if $self->_root;
  my $url = $self->url('/redfish/v1/');
  my $result;
  if ( !eval { $result = $self->send_request( GET => $url ); 1 } ) {
    my $error = $@;
    die $error unless blessed $error && $error->isa( $self->api_error_class ) && $error->is_unauthorized;
    # the service root is meant to be readable without a login; a controller
    # that wants one anyway gets the credentials
    $result = $self->send_request( GET => $url, basic => [ $self->username, $self->password ] );
  }
  $self->api_error_class->throw(
    message     => 'GET '.$url.' did not answer with a Redfish service root; is Redfish enabled on this iDRAC?',
    http_status => $result->{status}
  ) unless ref $result->{data} eq 'HASH' && defined $result->{data}{RedfishVersion};
  return $self->_root( $result->{data} );
}

=method root

The service root document. Read once and kept.

=cut

sub login {
  my ( $self ) = @_;
  my $links = $self->root->{Links};
  my $path  = ref $links eq 'HASH' && ref $links->{Sessions} eq 'HASH' ? $links->{Sessions}{'@odata.id'} : undef;
  $self->api_error_class->throw( message => 'the service root of '.$self->base_url.' names no session collection', http_status => 200 )
    unless defined $path;
  my $url    = $self->url($path);
  my $result = $self->send_request( POST => $url, json => { UserName => $self->username, Password => $self->password } );
  $self->api_error_class->throw( message => 'POST '.$url.' answered without an X-Auth-Token', http_status => $result->{status} )
    unless defined $result->{token};
  $self->_token( $result->{token} );
  $self->_session_path( $self->path_of( $result->{location} ) // ( ref $result->{data} eq 'HASH' ? $result->{data}{'@odata.id'} : undef ) );
  return 1;
}

=method login

Creates a session. Called for you by the first request; the session
collection is taken from the service root, because its path differs between
the generations.

=cut

sub forget_session {
  my ( $self ) = @_;
  $self->_token(undef);
  $self->_session_path(undef);
  return;
}

=method forget_session

Drops the token without telling the controller, for when the controller has
dropped the session itself.

=cut

sub logout {
  my ( $self ) = @_;
  my $token = $self->_token;
  my $path  = $self->_session_path;
  $self->forget_session;
  return 0 unless defined $token && defined $path;
  $self->send_request( DELETE => $self->url($path), token => $token );
  return 1;
}

=method logout

Ends the session, if there is one. An iDRAC allows only a few sessions at a
time and frees an abandoned one only after a timeout, so call this when you
are done. The object also does it when it is destroyed.

=cut

sub DEMOLISH {
  my ( $self ) = @_;
  local ( $@, $!, $? );
  eval { $self->logout };
  return;
}

sub request {
  my ( $self, $method, $path, %arg ) = @_;
  my $url = $self->url($path);
  return $self->send_request( $method => $url, %arg, basic => [ $self->username, $self->password ] ) unless $self->session;
  $self->login unless defined $self->_token;
  my $result;
  return $result if eval { $result = $self->send_request( $method => $url, %arg, token => $self->_token ); 1 };
  my $error = $@;
  die $error unless blessed $error && $error->isa( $self->api_error_class ) && $error->is_unauthorized;
  # the session ran out or the controller was restarted: one new login, one more try
  $self->forget_session;
  $self->login;
  return $self->send_request( $method => $url, %arg, token => $self->_token );
}

=method request

    my $result = $redfish->request( PATCH => $path, json => \%body );

One authenticated request. Returns C<status>, C<data>, C<location> and
C<token>, see L<WWW::iDRAC::Role::HTTP/read_response>. A refused token leads
to exactly one new login and one more try.

=cut

sub get    { $_[0]->request( GET => $_[1] )->{data} }
sub post   { $_[0]->request( POST => $_[1], json => $_[2] // {} )->{data} }
sub patch  { $_[0]->request( PATCH => $_[1], json => $_[2] // {} )->{data} }
sub delete { $_[0]->request( DELETE => $_[1] )->{data} }

=method get

    my $doc = $redfish->get($path);

=method post

    my $doc = $redfish->post( $path, \%body );

=method patch

    my $doc = $redfish->patch( $path, \%body );

=method delete

    $redfish->delete($path);

The four verbs. Each returns the decoded document of the answer, or C<undef>
when the answer has no body.

=cut

sub members {
  my ( $self, $path, %arg ) = @_;
  my $limit = $arg{limit};
  WWW::iDRAC::Error::Validation->throw( message => 'limit is a positive number, got '.$limit )
    if defined $limit && $limit !~ /\A[1-9][0-9]*\z/;
  my ( @docs, %seen );
  while ( defined $path && !$seen{$path}++ ) {
    my $collection = $self->get($path);
    last unless ref $collection eq 'HASH';
    for my $member ( ref $collection->{Members} eq 'ARRAY' ? @{ $collection->{Members} } : () ) {
      next unless ref $member eq 'HASH';
      # a member that carries more than its address is already the document
      push @docs, keys %$member > 1 || !defined $member->{'@odata.id'} ? $member : $self->get( $member->{'@odata.id'} );
      return @docs if defined $limit && @docs >= $limit;
    }
    $path = $self->path_of( $collection->{'Members@odata.nextLink'} );
  }
  return @docs;
}

=method members

    my @docs = $redfish->members( $path, limit => 50 );

The entries of a collection as documents, in the order the controller lists
them. Where the controller puts the whole entries into C<Members> they are
taken as they are; where it puts only addresses there, each one is fetched,
because old firmware does not know C<$expand>. Further pages are followed.
C<limit> caps the number of entries and so the number of requests.

=cut

sub locate {
  my ( $self, $kind ) = @_;
  WWW::iDRAC::Error::Validation->throw( message => 'locate knows Systems, Chassis and Managers, got '.( $kind // 'nothing' ) )
    unless defined $kind && $kind =~ /\A(?:Systems|Chassis|Managers)\z/;
  my $located = $self->_located;
  return $located->{$kind} if exists $located->{$kind};
  my $path;
  if ( $kind ne 'Systems' && defined( my $system = $self->locate('Systems') ) ) {
    # the system says which chassis holds it and which manager manages it
    my $doc   = $self->get($system);
    my $links = ref $doc eq 'HASH' ? $doc->{Links} : undef;
    my $list  = ref $links eq 'HASH' ? $links->{ $kind eq 'Chassis' ? 'Chassis' : 'ManagedBy' } : undef;
    ( $path ) = map { $_->{'@odata.id'} } grep { ref $_ eq 'HASH' && defined $_->{'@odata.id'} } ref $list eq 'ARRAY' ? @$list : ();
  }
  if ( !defined $path ) {
    my $collection = $self->root->{$kind};
    if ( ref $collection eq 'HASH' && defined $collection->{'@odata.id'} ) {
      my $doc = $self->get( $collection->{'@odata.id'} );
      ( $path ) = map { $_->{'@odata.id'} } grep { ref $_ eq 'HASH' && defined $_->{'@odata.id'} } ref $doc->{Members} eq 'ARRAY' ? @{ $doc->{Members} } : ();
    }
  }
  return $located->{$kind} = $path;
}

=method locate

    my $path = $redfish->locate('Systems');    # or Chassis, Managers

The path of the system, of the chassis that holds it and of the manager that
manages it, or C<undef> when the controller has none. Found through the
collections of the service root and the links of the system, not through
fixed names, and remembered for the lifetime of the object. Readings and
states are never remembered.

=cut

1;
