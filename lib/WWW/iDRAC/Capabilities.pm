package WWW::iDRAC::Capabilities;

# ABSTRACT: What this iDRAC is and what it can do

use Moo;
use Scalar::Util qw( blessed );
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

Generation, model, firmware and Redfish version come from Redfish. The
license does not: it is read over racadm, on the first call of L</license>
or L</facts>. L</supports> opens an SSH connection as well when it is asked
about a method served over racadm (C<bios.*>, C<jobs.*>, C<virtual_media.*>),
because the controller itself is asked. Whoever only wants the generation,
and asks L</supports> about the Redfish areas only, never opens one.

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

has racadm => ( is => 'ro' );

=attr racadm

The L<WWW::iDRAC::Racadm> transport the license is read through. Without
it, or with it switched off, the license is C<undef>.

=cut

has _redfish_facts => ( is => 'lazy' );

sub _build__redfish_facts {
  my ( $self ) = @_;
  my %doc = ( root => $self->redfish->root );
  for my $part ( [ system => 'Systems' ], [ manager => 'Managers' ] ) {
    my $path = $self->redfish->locate( $part->[1] );
    my $doc  = defined $path ? $self->redfish->get($path) : undef;
    $doc{ $part->[0] } = ref $doc eq 'HASH' ? $doc : {};
  }
  return $self->facts_from(%doc);
}

has license => ( is => 'lazy' );

sub _build_license {
  my ( $self ) = @_;
  my $racadm = $self->racadm;
  return unless $racadm && $racadm->enabled;
  my $text;
  if ( !eval { $text = $racadm->run( license => 'view' ); 1 } ) {
    my $error = $@;
    # what says racadm is not to be had here is undef, as the areas served
    # over it are Unsupported for it (WWW::iDRAC::Role::Racadm): nothing on
    # the SSH port, or racadm refuses to show the license. A failure on the
    # way, a refused login or host key, a timeout, is thrown and not kept.
    return if blessed $error && $error->isa('WWW::iDRAC::Error::Network') && ( $error->cause // '' ) eq 'refused';
    return if blessed $error && $error->isa( $racadm->api_error_class );
    die $error;
  }
  return $self->license_from($text);
}

has facts => ( is => 'lazy' );

sub _build_facts {
  my ( $self ) = @_;
  return { %{ $self->_redfish_facts }, license => $self->license };
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

The five facts below as one hash. Reading it reads the license too.

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

my %RANK = ( basic => 1, express => 2, enterprise => 3, datacenter => 4 );

sub license_from {
  my ( $class, $raw ) = @_;
  my $text = defined $raw && !ref $raw ? $raw : '';
  my ($best) = sort { $RANK{$b} <=> $RANK{$a} }
    map { lc $_ } $text =~ /^\s*License Description\s*=.*?\b(basic|express|enterprise|datacenter)\b/gim;
  return $best;
}

=attr license

C<basic>, C<express>, C<enterprise>, C<datacenter>, or C<undef> where racadm
is not to be had: it is switched off (C<< ssh => 0 >>), the SSH port refuses
the connection, racadm answers the command with an error
(L<WWW::iDRAC::Error::API>), or the controller lists no license. Of several
licenses the highest counts. Everything else is thrown and not remembered, so
the next read tries again: L<WWW::iDRAC::Error::Validation> (a bad
C<ssh_opts> entry, say) and every other L<WWW::iDRAC::Error::Network>, that
is a refused login, a host key that is unknown or changed, a timeout, an
unreachable controller and the rest.

=method license_from

    my $license = WWW::iDRAC::Capabilities->license_from($text);

The license out of what C<racadm license view> printed, from the
C<License Description> lines (C<iDRAC8 Express License>), without I/O.

=cut

sub generation      { $_[0]->_redfish_facts->{generation} }
sub model           { $_[0]->_redfish_facts->{model} }
sub firmware        { $_[0]->_redfish_facts->{firmware} }
sub redfish_version { $_[0]->_redfish_facts->{redfish_version} }

=method generation

7, 8, 9 or 10, or C<undef> when the controller does not say.

=method model

The model of the server, for example C<PowerEdge T330>.

=method firmware

The firmware version of the iDRAC.

=method redfish_version

The version of Redfish the controller speaks.

=cut

sub supports {
  my ( $self, $name ) = @_;
  my ( $area, $method ) = defined $name && !ref $name ? $name =~ /\A([a-z_]+)\.([a-z_]+)\z/ : ();
  WWW::iDRAC::Error::Validation->throw( message => 'unknown capability '.( $name // '' ) )
    unless defined $area && $self->areas->{$area};
  return $self->areas->{$area}->supports($method);
}

=method supports

    if ( $cap->supports('power.cycle') ) { ... }

True when this controller can serve the method of that name, given as
C<area.method>. The answer comes from what the controller offers, the
resources it has and the values its actions allow, not from a table of
versions. For C<bios.*>, C<jobs.*> and C<virtual_media.*> that means asking
racadm over SSH, so the call can throw what a racadm command throws
(L<WWW::iDRAC::Error::Network>, for one); it answers false where the
license is missing, nothing listens on the SSH port or racadm is switched
off. A name that
is no method is a L<WWW::iDRAC::Error::Validation>.

=cut

1;
