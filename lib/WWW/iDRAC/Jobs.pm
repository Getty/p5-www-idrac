package WWW::iDRAC::Jobs;

# ABSTRACT: The job queue of the iDRAC, over racadm

use Moo;
use WWW::iDRAC::Error::Validation;
use WWW::iDRAC::Util qw( number text );
use namespace::autoclean;

our $VERSION = '0.001';

sub area { 'jobs' }

with 'WWW::iDRAC::Role::Racadm';

=synopsis

    for my $job ( @{ $idrac->jobs->list } ) {
      printf "%s %-12s %3s%% %s\n", $job->{id}, $job->{status}, $job->{percent_complete} // '-', $job->{message} // '';
    }

    my $job = $idrac->jobs->wait( $id, timeout => 600 );
    print $job ? $job->{status} : 'still running', "\n";

=description

The queue of work the controller has been given: BIOS changes that wait for
a restart, firmware updates, an erase of the system. Redfish on an iDRAC 7
or 8 does not show it; this class is served over racadm.

A job is a hash with the keys C<id> (C<JID_...>), C<name>, C<status>
(what the controller says, for example C<Completed>, C<Scheduled>,
C<Running>), C<message> (the text after the message number),
C<message_id> (the number, for example C<SYS018>), C<percent_complete>,
C<start_time> and C<expiration_time> (as the controller prints them,
C<Now> and C<Not Applicable> included) and C<finished>, true once the
status says completed, failed or cancelled. The
identifiers of the controller are not rewritten.

Of the statuses, only C<Completed> was seen, on an iDRAC 7. The others named
here, and the way C<finished> recognises them (the words I<completed>,
I<failed> and I<canceled> or I<cancelled> in the status), were not seen.

=cut

my $JOB_ID = qr/\A(?:JID|RID)_[0-9]+\z/;

sub _job_id {
  my ( $class, $id ) = @_;
  WWW::iDRAC::Error::Validation->throw( message => 'a job id is JID_ or RID_ and digits, like JID_123456789012' )
    unless defined $id && !ref $id && $id =~ $JOB_ID;
  return $id;
}

sub jobs_from {
  my ( $class, $raw ) = @_;
  my @jobs;
  for my $block ( $class->racadm_class->blocks_from($raw) ) {
    next unless $block->{kind} eq 'Job ID';
    my %value = map { $_->{name} => $_->{value} } @{ $block->{entries} };
    my ( $message_id, $message ) = ( text( $value{Message} ) // '' ) =~ /\A([A-Z]{2,5}[0-9]{1,5})\s*:\s*(.*)\z/s;
    $message = text( $value{Message} ) unless defined $message_id;
    my $status = text( $value{Status} );
    push @jobs, {
      id               => text( $block->{id} ),
      name             => text( $value{'Job Name'} ),
      status           => $status,
      message          => text($message),
      message_id       => $message_id,
      percent_complete => number( $value{'Percent Complete'} ),
      start_time       => text( $value{'Start Time'} ),
      expiration_time  => text( $value{'Expiration Time'} ),
      finished         => defined $status && $status =~ /\b(?:completed|failed|cancel+ed)\b/i ? 1 : 0
    };
  }
  return \@jobs;
}

sub list {
  my ( $self ) = @_;
  return $self->jobs_from( $self->racadm_run( list => jobqueue => 'view' ) );
}

=method list

    my $jobs = $idrac->jobs->list;

All jobs in the queue, as the controller lists them; an empty array ref when
there are none.

=method jobs_from

    my $jobs = WWW::iDRAC::Jobs->jobs_from($text);

The translation behind L</list> and L</get>, without I/O.

=cut

sub get {
  my ( $self, $id ) = @_;
  $self->_job_id($id);
  my ($job) = @{ $self->jobs_from( $self->racadm_run( get => jobqueue => 'view', '-i', $id ) ) };
  $self->unsupported( get => 'the controller printed no job for '.$id ) unless $job;
  return $job;
}

=method get

    my $job = $idrac->jobs->get('JID_123456789012');

One job. A job the controller does not have is L<WWW::iDRAC::Error::API>
with C<is_not_found>; an identifier that is not one is
L<WWW::iDRAC::Error::Validation>.

=cut

sub delete {
  my ( $self, $id ) = @_;
  $self->_job_id($id);
  $self->racadm_run( delete => jobqueue => 'delete', '-i', $id );
  return 1;
}

=method delete

    $idrac->jobs->delete('JID_123456789012');

Removes one job from the queue and returns true. The controller refuses a job
that is running; that refusal is L<WWW::iDRAC::Error::API>.

Not run against hardware; tested against a fake only.

=cut

sub wait {
  my ( $self, $id, %arg ) = @_;
  $self->_job_id($id);
  my $interval = delete $arg{interval} // 5;
  my $timeout  = delete $arg{timeout} // 600;
  WWW::iDRAC::Error::Validation->throw( message => 'wait takes interval and timeout only' ) if %arg;
  for my $pair ( [ interval => $interval ], [ timeout => $timeout ] ) {
    WWW::iDRAC::Error::Validation->throw( message => 'wait '.$pair->[0].' is a non-negative number of seconds' )
      unless defined $pair->[1] && !ref $pair->[1] && $pair->[1] =~ /\A[0-9]+\z/;
  }
  my $deadline = time + $timeout;
  while (1) {
    my $job = $self->get($id);
    return $job if $job->{finished};
    return undef if time >= $deadline;
    sleep $interval if $interval;
  }
}

=method wait

    my $job = $idrac->jobs->wait( $id, timeout => 600, interval => 5 );

Asks for the job every C<interval> seconds, 5 by default, until its status
says it is finished, and returns the job then. C<undef> when C<timeout>
seconds, 600 by default, have passed first. That the job is finished says
nothing about whether it worked: look at C<status> and C<message>.

=cut

sub probe_list   { $_[0]->list }
sub probe_get    { $_[0]->list }
sub probe_delete { $_[0]->list }
sub probe_wait   { $_[0]->list }

=method probe_list

=method probe_get

=method probe_delete

=method probe_wait

What L<WWW::iDRAC::Role::Area/supports> asks: all four read the queue.

=cut

1;
