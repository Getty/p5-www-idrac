package WWW::iDRAC::Power;

# ABSTRACT: Switching the server behind an iDRAC, and what it draws

use Moo;
use WWW::iDRAC::Error::Validation;
use WWW::iDRAC::Util qw( list_of number state_of );
use namespace::autoclean;

our $VERSION = '0.001';

sub area { 'power' }

with 'WWW::iDRAC::Role::Capability';

=synopsis

    my $power = $idrac->power;

    $power->off;                                    # ask the operating system to shut down
    $power->off( force => 1 ) unless $power->wait_for( 'off', timeout => 300 );
    $power->on;

    print $power->consumption->{watts}, " W\n";

=description

The switching methods return as soon as the controller has accepted the
order; the server takes its time. L</wait_for> waits for the result.

Before an order is sent, the reset type it needs is checked against the ones
the controller offers. A type that is not offered is
L<WWW::iDRAC::Error::Unsupported> and nothing is sent.

=cut

# what each method asks for, gently and with force
my %RESET = (
  on      => [ 'On',               'On' ],
  off     => [ 'GracefulShutdown', 'ForceOff' ],
  restart => [ 'GracefulRestart',  'ForceRestart' ],
  cycle   => [ 'PowerCycle',       'PowerCycle' ]
);

sub state {
  my ( $self ) = @_;
  return state_of( $self->resource( Systems => 'state' )->{PowerState} );
}

=method state

C<on> or C<off>. While the server is on its way the controller may name a
state in between, which is returned in the same form, for example
C<powering_on>.

=cut

sub reset_action {
  my ( $self, $method, $force ) = @_;
  my $type   = $RESET{$method}[ $force ? 1 : 0 ];
  my $doc    = $self->resource( Systems => $method );
  my $action = ref $doc->{Actions} eq 'HASH' ? $doc->{Actions}{'#ComputerSystem.Reset'} : undef;
  $self->unsupported( $method, 'the system offers no reset action' ) unless ref $action eq 'HASH' && defined $action->{target};
  my $allowed = $action->{'ResetType@Redfish.AllowableValues'};
  $self->unsupported( $method, 'reset type '.$type.' is not offered, only '.join( ', ', grep { defined } @$allowed ) )
    if ref $allowed eq 'ARRAY' && !grep { defined && $_ eq $type } @$allowed;
  return ( $action->{target}, $type );
}

=method reset_action

    my ( $target, $type ) = $power->reset_action( off => $force );

Where a switching method sends its order and with which reset type, or
L<WWW::iDRAC::Error::Unsupported>.

=cut

sub _reset {
  my ( $self, $method, @args ) = @_;
  WWW::iDRAC::Error::Validation->throw(
    message => $method.' takes no positional arguments'
  ) if @args % 2;
  my %arg = @args;
  my @bad = grep { $_ ne 'force' } keys %arg;
  WWW::iDRAC::Error::Validation->throw(
    message => $method.' takes only \'force\', got '.join( ', ', sort @bad )
  ) if @bad;
  my ( $target, $type ) = $self->reset_action( $method, $arg{force} );
  $self->redfish->post( $target, { ResetType => $type } );
  return 1;
}

sub on      { my $self = shift; $self->_reset( on      => @_ ) }
sub off     { my $self = shift; $self->_reset( off     => @_ ) }
sub restart { my $self = shift; $self->_reset( restart => @_ ) }
sub cycle   { my $self = shift; $self->_reset( cycle   => @_ ) }

=method on

Turns the server on.

=method off

    $power->off;
    $power->off( force => 1 );

Asks the operating system to shut down. With C<force> the power is cut.

=method restart

    $power->restart;
    $power->restart( force => 1 );

Asks the operating system to restart. With C<force> the server is reset.

=method cycle

Power off and on again.

=cut

sub wait_for {
  my ( $self, $state, %arg ) = @_;
  WWW::iDRAC::Error::Validation->throw( message => 'wait_for waits for on or off, got '.( $state // 'nothing' ) )
    unless defined $state && ( $state eq 'on' || $state eq 'off' );
  my $interval = $arg{interval} // 5;
  my $deadline = time + ( $arg{timeout} // 120 );
  while (1) {
    return 1 if ( $self->state // '' ) eq $state;
    return 0 if time >= $deadline;
    sleep $interval if $interval;
  }
}

=method wait_for

    my $reached = $power->wait_for( 'off', timeout => 120, interval => 5 );

Asks for L</state> every C<interval> seconds until it is the wanted one.
True when it was reached, false when C<timeout> seconds have passed.

=cut

sub _power_document {
  my ( $self, $method ) = @_;
  return $self->linked_document( $self->resource( Chassis => $method ), Power => $method );
}

sub consumption {
  my ( $self ) = @_;
  return $self->consumption_from( $self->_power_document('consumption') );
}

sub consumption_from {
  my ( $class, $doc ) = @_;
  my ( $control ) = list_of( ref $doc eq 'HASH' ? $doc->{PowerControl} : undef );
  my $metrics = $control && ref $control->{PowerMetrics} eq 'HASH' ? $control->{PowerMetrics} : {};
  return {
    watts          => number( $control ? $control->{PowerConsumedWatts} : undef ),
    average_watts  => number( $metrics->{AverageConsumedWatts} ),
    min_watts      => number( $metrics->{MinConsumedWatts} ),
    max_watts      => number( $metrics->{MaxConsumedWatts} ),
    capacity_watts => number( $control ? $control->{PowerCapacityWatts} : undef )
  };
}

=method consumption

C<watts> the server draws now, C<average_watts>, C<min_watts> and
C<max_watts> over the interval the controller measures, and
C<capacity_watts>.

=method consumption_from

    my $consumption = WWW::iDRAC::Power->consumption_from($power_document);

The translation behind L</consumption>, without I/O.

=cut

sub probe_state       { $_[0]->resource( Systems => 'state' ) }
sub probe_wait_for    { $_[0]->resource( Systems => 'wait_for' ) }
sub probe_on          { $_[0]->reset_action('on') }
sub probe_off         { $_[0]->reset_action('off') }
sub probe_restart     { $_[0]->reset_action('restart') }
sub probe_cycle       { $_[0]->reset_action('cycle') }
sub probe_consumption { $_[0]->_power_document('consumption') }

=method probe_state

=method probe_wait_for

=method probe_on

=method probe_off

=method probe_restart

=method probe_cycle

=method probe_consumption

What L<WWW::iDRAC::Role::Capability/supports> asks. C<probe_off> and
C<probe_restart> answer for the gentle form.

=cut

1;
