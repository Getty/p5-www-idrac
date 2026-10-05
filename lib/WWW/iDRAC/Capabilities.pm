package WWW::iDRAC::Capabilities;

# ABSTRACT: What this iDRAC is and what it can do

use Moo;
use Types::Standard qw( HashRef );
use WWW::iDRAC::Error::Validation;
use WWW::iDRAC::Util qw( text );
use namespace::autoclean;

our $VERSION = '0.001';

=synopsis

    my $cap = $idrac->capabilities;

    printf "iDRAC %s, firmware %s, on a %s\n", $cap->generation // '?', $cap->firmware // '?', $cap->model // '?';

    $idrac->power->cycle if $cap->supports('power.cycle');

=description

The facts are read once, on first use. L</supports> asks the controller
each time, because what it offers can change with the state of the server.

=cut

has redfish => (
  is       => 'ro',
  required => 1
);

=attr redfish

Required. The L<WWW::iDRAC::Redfish> transport.

=cut

has areas => (
  is       => 'ro',
  isa      => HashRef,
  required => 1
);

=attr areas

Required. The capability objects by the name of their area.

=cut

has facts => ( is => 'lazy' );

sub _build_facts {
  my ( $self ) = @_;
  my %doc = ( root => $self->redfish->root );
  for my $part ( [ system => 'Systems' ], [ manager => 'Managers' ] ) {
    my $path = $self->redfish->locate( $part->[1] );
    my $doc  = defined $path ? $self->redfish->get($path) : undef;
    $doc{ $part->[0] } = ref $doc eq 'HASH' ? $doc : {};
  }
  return $self->facts_from(%doc);
}

sub facts_from {
  my ( $class, %doc ) = @_;
  return {
    generation      => $class->generation_from( $doc{manager}{Model} ),
    model           => text( $doc{system}{Model} ),
    firmware        => text( $doc{manager}{FirmwareVersion} ),
    redfish_version => text( $doc{root}{RedfishVersion} ),
    license         => undef
  };
}

=attr facts

The five facts below as one hash.

=method facts_from

    my $facts = WWW::iDRAC::Capabilities->facts_from( root => $root, system => $system, manager => $manager );

The translation behind L</facts>, without I/O.

=cut

sub generation_from {
  my ( $class, $model ) = @_;
  my ( $server ) = ( text($model) // '' ) =~ /\b([0-9]{2})G\b/ or return undef;
  return $server == 12 ? 7 : $server == 13 ? 8 : $server >= 14 && $server <= 16 ? 9 : $server >= 17 ? 10 : undef;
}

=method generation_from

    my $generation = WWW::iDRAC::Capabilities->generation_from('13G Monolithic');    # 8

The generation of the iDRAC out of the model the manager reports, which
names the generation of the server: 12G is iDRAC 7, 13G is iDRAC 8, 14G to
16G are iDRAC 9, 17G is iDRAC 10.

=cut

sub generation      { $_[0]->facts->{generation} }
sub model           { $_[0]->facts->{model} }
sub firmware        { $_[0]->facts->{firmware} }
sub redfish_version { $_[0]->facts->{redfish_version} }
sub license         { $_[0]->facts->{license} }

=method generation

7, 8, 9 or 10, or C<undef> when the controller does not say.

=method model

The model of the server, for example C<PowerEdge T330>.

=method firmware

The firmware version of the iDRAC.

=method redfish_version

The version of Redfish the controller speaks.

=method license

C<undef> in this version: the license is not read yet.

=cut

sub supports {
  my ( $self, $name ) = @_;
  my ( $area, $method ) = defined $name && !ref $name ? $name =~ /\A([a-z]+)\.([a-z_]+)\z/ : ();
  WWW::iDRAC::Error::Validation->throw( message => 'unknown capability '.( $name // '' ) )
    unless defined $area && $self->areas->{$area};
  return $self->areas->{$area}->supports($method);
}

=method supports

    if ( $cap->supports('power.cycle') ) { ... }

True when this controller can serve the method of that name, given as
C<area.method>. The answer comes from what the controller offers, the
resources it has and the values its actions allow, not from a table of
versions. A name that is no method is a L<WWW::iDRAC::Error::Validation>.

=cut

1;
