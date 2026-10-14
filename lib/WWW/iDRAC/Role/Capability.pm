package WWW::iDRAC::Role::Capability;

# ABSTRACT: What the capability classes of WWW::iDRAC share

use Scalar::Util qw( blessed );
use WWW::iDRAC::Error::Unsupported;
use WWW::iDRAC::Error::Validation;
use Moo::Role;

our $VERSION = '0.001';

with 'WWW::iDRAC::Role::Area';

=description

A capability class that is served over Redfish answers for one area
(C<system>, C<power>, C<sensors>, C<logs>, C<manager>). It reaches the
controller only through L</redfish>, returns translated data, never raw
documents, and turns a resource this controller does not have into
L<WWW::iDRAC::Error::Unsupported>. The classes that are served over racadm
use L<WWW::iDRAC::Role::Racadm> instead; what both share is
L<WWW::iDRAC::Role::Area>, with C<unsupported> and C<supports>.

Each public method C<x> has a C<probe_x> beside it, which fetches the
documents the method starts from, not only the links to them, and throws
where the method would. L<WWW::iDRAC::Role::Area/supports> is built on
those, so its answer comes from what the controller offers.

=cut

has redfish => (
  is       => 'ro',
  required => 1
);

=attr redfish

Required. The L<WWW::iDRAC::Redfish> transport.

=cut

sub _not_found {
  my ( $self, $error ) = @_;
  return blessed $error && $error->isa('WWW::iDRAC::Error::API') && $error->is_not_found;
}

sub fetch {
  my ( $self, $path, $method ) = @_;
  my $doc;
  if ( !eval { $doc = $self->redfish->get($path); 1 } ) {
    my $error = $@;
    $self->unsupported( $method, $path.' does not exist' ) if $self->_not_found($error);
    die $error;
  }
  $self->unsupported( $method, $path.' holds no document' ) unless ref $doc eq 'HASH';
  return $doc;
}

=method fetch

    my $doc = $self->fetch( $path, 'temperatures' );

A document. A 404, and an answer that is no document, are
L<WWW::iDRAC::Error::Unsupported> for the named method.

=cut

sub fetch_members {
  my ( $self, $path, $method, %arg ) = @_;
  my @docs;
  return grep { ref $_ eq 'HASH' } @docs if eval { @docs = $self->redfish->members( $path, %arg ); 1 };
  my $error = $@;
  if ( $self->_not_found($error) ) {
    my $error_path = $self->_path_of_error($error);
    return $self->unsupported( $method, $path.' does not exist' ) if defined $error_path && $error_path eq $path;
  }
  die $error;
}

# the path an API error was raised for, or undef; lets fetch_members tell
# a missing collection from a missing member
sub _path_of_error {
  my ( $self, $error ) = @_;
  return undef unless blessed $error && $error->isa('WWW::iDRAC::Error');
  my ( $url ) = "$error" =~ /\AGET\s+(\S+)\s+failed/;
  return undef unless defined $url;
  return $self->redfish->path_of($url);
}

=method fetch_members

    my @docs = $self->fetch_members( $path, 'processors', limit => 10 );

The entries of a collection, with the same treatment of a 404.

=cut

sub resource {
  my ( $self, $kind, $method ) = @_;
  my $path;
  if ( !eval { $path = $self->redfish->locate($kind); 1 } ) {
    my $error = $@;
    $self->unsupported( $method, 'a document on the way to the '.$kind.' resource does not exist' ) if $self->_not_found($error);
    die $error;
  }
  $self->unsupported( $method, 'the controller has no '.$kind.' resource' ) unless defined $path;
  return $self->fetch( $path, $method );
}

=method resource

    my $system = $self->resource( Systems => 'info' );

The current document of the system, the chassis or the manager.

=cut

sub linked_document {
  my ( $self, $doc, $key, $method ) = @_;
  return $self->fetch( $self->linked_path( $doc, $key, $method ), $method );
}

=method linked_document

    my $thermal = $self->linked_document( $chassis, Thermal => 'temperatures' );

The document behind L</linked_path>.

=cut

sub linked_path {
  my ( $self, $doc, $key, $method ) = @_;
  my $link = ref $doc eq 'HASH' ? $doc->{$key} : undef;
  return $link->{'@odata.id'} if ref $link eq 'HASH' && defined $link->{'@odata.id'};
  $self->unsupported( $method, 'the controller has no '.$key.' resource' );
}

=method linked_path

    my $path = $self->linked_path( $chassis, Thermal => 'temperatures' );

The address a document gives for one of its parts.

=cut

1;
