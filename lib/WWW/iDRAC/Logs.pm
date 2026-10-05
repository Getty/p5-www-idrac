package WWW::iDRAC::Logs;

# ABSTRACT: The system event log and the lifecycle log of an iDRAC

use Moo;
use WWW::iDRAC::Util qw( text );
use namespace::autoclean;

our $VERSION = '0.001';

sub area { 'logs' }

with 'WWW::iDRAC::Role::Capability';

=synopsis

    print $_->{created}, ' ', $_->{severity}, ' ', $_->{message}, "\n" for @{ $idrac->logs->sel( limit => 20 ) };

    $idrac->logs->clear_sel;

=description

The two logs an iDRAC keeps: the system event log of the hardware and the
lifecycle log of the controller. Both are found through the log services the
manager lists, by the name the service gives itself or the last part of its
address: C<SEL> or C<Sel>, and C<LC> or C<Lclog>.

C<limit> is the number of entries fetched, 50 unless given, taken from the
front of the list as the controller serves it, which is newest first on an
iDRAC. The entries fetched are returned newest first.

=cut

# what a log service is called: an iDRAC 7 and 8 name theirs SEL and LC, and
# serve them at .../LogServices/Sel and .../LogServices/Lclog
my %NAMES = ( sel => [qw( sel )], lclog => [qw( lclog lc )] );

sub service {
  my ( $self, $id, $method ) = @_;
  my $path = $self->linked_path( $self->resource( Managers => $method ), LogServices => $method );
  for my $service ( $self->fetch_members( $path, $method ) ) {
    my %called = map { lc $_ => 1 } grep { defined } text( $service->{Id} ), ( ( $service->{'@odata.id'} // '' ) =~ m{([^/]+)/?\z} )[0];
    return $service if grep { $called{$_} } @{ $NAMES{$id} };
  }
  $self->unsupported( $method, 'the controller has no log service '.$id );
}

=method service

    my $doc = $logs->service( sel => 'clear_sel' );

The document of the log service C<sel> or C<lclog>.

=cut

sub entries {
  my ( $self, $id, $method, %arg ) = @_;
  my $path    = $self->linked_path( $self->service( $id, $method ), Entries => $method );
  my @entries = map { $self->entry_from($_) } $self->fetch_members( $path, $method, limit => $arg{limit} // 50 );
  return [ sort { ( $b->{created} // '' ) cmp ( $a->{created} // '' ) } @entries ];
}

sub entry_from {
  my ( $class, $doc ) = @_;
  my $severity = text( $doc->{Severity} );
  return {
    id         => text( $doc->{Id} ),
    created    => text( $doc->{Created} ),
    severity   => defined $severity ? lc $severity : undef,
    message    => text( $doc->{Message} ),
    # firmware 2.50 of an iDRAC 8 spells the key MessageID
    message_id => text( $doc->{MessageId} ) // text( $doc->{MessageID} )
  };
}

=method entries

    my $entries = $logs->entries( sel => 'sel', limit => 50 );

What L</sel> and L</lifecycle> are made of.

=method entry_from

    my $entry = WWW::iDRAC::Logs->entry_from($entry_document);

The translation of one entry, without I/O.

=cut

sub sel       { my ( $self, %arg ) = @_; $self->entries( sel   => 'sel',       %arg ) }
sub lifecycle { my ( $self, %arg ) = @_; $self->entries( lclog => 'lifecycle', %arg ) }

=method sel

    my $entries = $logs->sel( limit => 50 );

The system event log. One hash per entry: C<id>, C<created>, C<severity> in
lower case, C<message>, C<message_id>.

=method lifecycle

    my $entries = $logs->lifecycle( limit => 50 );

The lifecycle log, in the same form.

=cut

sub clear_action {
  my ( $self ) = @_;
  my $service = $self->service( sel => 'clear_sel' );
  my $action  = ref $service->{Actions} eq 'HASH' ? $service->{Actions}{'#LogService.ClearLog'} : undef;
  $self->unsupported( clear_sel => 'the log service offers no clear action' ) unless ref $action eq 'HASH' && defined $action->{target};
  return $action->{target};
}

sub clear_sel {
  my ( $self ) = @_;
  $self->redfish->post( $self->clear_action, {} );
  return 1;
}

=method clear_sel

Empties the system event log.

=method clear_action

Where L</clear_sel> sends its order, or L<WWW::iDRAC::Error::Unsupported>.

=cut

sub probe_sel       { $_[0]->linked_document( $_[0]->service( sel   => 'sel' ),       Entries => 'sel' ) }
sub probe_lifecycle { $_[0]->linked_document( $_[0]->service( lclog => 'lifecycle' ), Entries => 'lifecycle' ) }
sub probe_clear_sel { $_[0]->clear_action }

=method probe_sel

=method probe_lifecycle

=method probe_clear_sel

What L<WWW::iDRAC::Role::Capability/supports> asks.

=cut

1;
