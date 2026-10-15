#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use FakeRacadm;
use iDRACShapes;
use WWW::iDRAC;

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

sub setup {
  my ( %arg ) = @_;
  my $racadm = FakeRacadm->new(%arg);
  my $idrac  = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, racadm => $racadm->transport );
  return ( $idrac, $racadm );
}

my @JOBS = (
  { id => 'JID_000000000001', name => 'System_Erase', status => 'Completed', start => 'Now', message => 'SYS018: Job completed successfully.', percent => 100 },
  { id => 'JID_000000000002', name => 'ConfigBIOS:BIOS.Setup.1-1', status => 'Running', start => 'TIME_NOW', message => 'JCP007: Job in progress.', percent => 40 }
);

subtest 'list and get' => sub {
  my ( $idrac, $fake ) = setup( jobs => [ map { {%$_} } @JOBS ] );
  my $list = $idrac->jobs->list;
  shape_ok( $list, 'jobs.list' );
  is( scalar @$list, 2, 'two jobs' );
  is_deeply( $list->[0], {
    id => 'JID_000000000001', name => 'System_Erase', status => 'Completed', message => 'Job completed successfully.', message_id => 'SYS018',
    percent_complete => 100, start_time => 'Now', expiration_time => 'Not Applicable', finished => 1
  }, 'translated, the message number apart' );
  is( $list->[1]{finished}, 0, 'a running job is not finished' );
  is( $list->[1]{expiration_time}, 'Not Applicable', 'the expiration time as the controller prints it' );
  is( $list->[1]{percent_complete}, 40, 'with its progress' );

  my $job = $idrac->jobs->get('JID_000000000002');
  shape_ok( $job, 'jobs.get' );
  is_deeply( $job, $list->[1], 'one job is what the list shows' );
  is( $fake->commands->[-1], 'racadm jobqueue view -i JID_000000000002', 'by id' );

  my $e = error_of { $idrac->jobs->get('JID_000000000009') };
  isa_ok( $e, 'WWW::iDRAC::Error::API', 'a job it does not have' );
  ok( $e->is_not_found, 'is a not found' );
  for my $bad ( undef, '', '5', 'JID_', 'JID_12 x', 'JID_1; reboot', [], "JID_1\n" ) {
    isa_ok( error_of { $idrac->jobs->get($bad) }, 'WWW::iDRAC::Error::Validation', 'id '.( $bad // 'undef' ) );
  }
  is_deeply( ( setup() )[0]->jobs->list, [], 'an empty queue is an empty list' );
};

subtest 'jobs_from' => sub {
  my $jobs = WWW::iDRAC::Jobs->jobs_from( <<'TEXT' );
-------------------------JOB QUEUE------------------------
[Job ID=JID_000000000001]
Job Name=Firmware Update: BIOS
Status=Completed with Errors
Start Time=[20261014120000]
Expiration Time=[TIME_NA]
Message=[RED001: no number after the colon in the next one]
Percent Complete=[NA]
[Job ID=RID_000000000002]
Job Name=Reboot
Status=Reboot Failed
Message=[Something without a number.]
[Job ID=JID_000000000003]
Status=Scheduled
----------------------------------------------------------
TEXT
  is( scalar @$jobs, 3, 'three jobs' );
  is( $jobs->[0]{percent_complete}, undef, 'a progress that is no number is undef' );
  is( $jobs->[0]{finished}, 1, 'completed with errors is finished' );
  is( $jobs->[1]{finished}, 1, 'reboot failed is finished' );
  is( $jobs->[1]{message}, 'Something without a number.', 'a message without a number' );
  is( $jobs->[1]{message_id}, undef, 'has no id' );
  is( $jobs->[2]{finished}, 0, 'scheduled is not' );
  is( $jobs->[2]{name}, undef, 'a key that is missing is undef' );
  is_deeply( WWW::iDRAC::Jobs->jobs_from(undef), [], 'nothing' );
  is( $jobs->[0]{expiration_time}, 'TIME_NA', 'the expiration time as printed, brackets removed' );
  is( $jobs->[1]{expiration_time}, undef, 'undef where missing' );
  is( $jobs->[0]{start_time}, '20261014120000', 'the start time' );

  my $other = WWW::iDRAC::Jobs->jobs_from( "[Key=BIOS.Setup.1-1#BiosBootSettings]\nStatus=Completed\n[Job ID=JID_000000000007]\nStatus=Scheduled\n" );
  is_deeply( [ map { $_->{id} } @$other ], ['JID_000000000007'], 'a [Key=...] block is no job' );
  is_deeply( WWW::iDRAC::Jobs->jobs_from("[Key=BIOS.Setup.1-1#A]\nStatus=Completed\n"), [], 'and alone it is no job at all' );

  my %finished = ( Cancelled => 1, Canceled => 1, Failed => 1, 'Completed with Errors' => 1, Completed => 1, Running => 0, Scheduled => 0, New => 0, 'Downloading' => 0 );
  for my $status ( sort keys %finished ) {
    my ($job) = @{ WWW::iDRAC::Jobs->jobs_from("[Job ID=JID_1]\nStatus=$status\n") };
    is( $job->{finished}, $finished{$status}, 'finished for '.$status );
  }
  my ($nostatus) = @{ WWW::iDRAC::Jobs->jobs_from("[Job ID=JID_1]\nJob Name=x\n") };
  is( $nostatus->{finished}, 0, 'a job without a status is not finished' );
};

subtest 'get without a job in the answer' => sub {
  my $fake  = FakeRacadm->new( replies => { 'racadm jobqueue view -i JID_000000000001' => "-------- JOB --------\n------------\n" } );
  my $idrac = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, racadm => $fake->transport );
  my $e = error_of { $idrac->jobs->get('JID_000000000001') };
  isa_ok( $e, 'WWW::iDRAC::Error::Unsupported', 'a text without a job block' );
  is( $e && $e->capability, 'jobs.get', 'for the method' );
  like( $e && $e->reason, qr/JID_000000000001/, 'which names the job' );
};

subtest 'delete' => sub {
  my ( $idrac, $fake ) = setup( jobs => [ map { {%$_} } @JOBS ] );
  is( $idrac->jobs->delete('JID_000000000001'), 1, 'returns true' );
  is( $fake->commands->[-1], 'racadm jobqueue delete -i JID_000000000001', 'the command' );
  is_deeply( [ map { $_->{id} } @{ $fake->jobs } ], ['JID_000000000002'], 'gone' );
  my $e = error_of { $idrac->jobs->delete('JID_000000000002') };
  isa_ok( $e, 'WWW::iDRAC::Error::API', 'a running job is refused' );
  is( $e->message_id, 'RAC1033', 'by the controller' );
  ok( $e->is_not_found ? 0 : 1, 'not as a missing one' );
  isa_ok( error_of { $idrac->jobs->delete('all') }, 'WWW::iDRAC::Error::Validation', 'not "all"' );
  isa_ok( error_of { $idrac->jobs->delete('--all') }, 'WWW::iDRAC::Error::Validation', 'not an option' );
  isa_ok( error_of { $idrac->jobs->delete('-d') }, 'WWW::iDRAC::Error::Validation', 'nor -d' );

  my $banner = FakeRacadm->new( replies => { 'racadm jobqueue delete -i JID_000000000001' => "Security banner of the site\nERROR: RAC1033: The job cannot be deleted.\n" } );
  my $bannered = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, racadm => $banner->transport );
  $e = error_of { $bannered->jobs->delete('JID_000000000001') };
  isa_ok( $e, 'WWW::iDRAC::Error::API', 'an error after a banner' );
  is( $e && $e->message_id, 'RAC1033', 'with its code' );
};

subtest 'wait' => sub {
  my ( $idrac, $fake ) = setup( jobs => [ map { {%$_} } @JOBS ] );
  my $job = $idrac->jobs->wait( 'JID_000000000001', timeout => 5, interval => 0 );
  is( $job->{status}, 'Completed', 'a finished job comes back at once' );
  is( scalar @{ $fake->commands }, 1, 'after one look' );

  # a job that is running and then completes, on the third look
  {
    my $looks = 0;
    my $fake2 = FakeRacadm->new( jobs => [ { %{ $JOBS[1] } } ] );
    my $orig  = FakeRacadm->can('_do_jobqueue');
    no warnings 'redefine';
    local *FakeRacadm::_do_jobqueue = sub {
      my ( $self, @arg ) = @_;
      $self->{jobs}[0]{status} = 'Completed' if ++$looks >= 3;
      return $orig->( $self, @arg );
    };
    my $idrac2 = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, racadm => $fake2->transport );
    $job = $idrac2->jobs->wait( 'JID_000000000002', timeout => 30, interval => 0 );
    is( $job->{status}, 'Completed', 'waited for it' );
    is( $looks, 3, 'looked three times' );
  }

  my ($running) = setup( jobs => [ { %{ $JOBS[1] } } ] );
  my $t = time;
  is( $running->jobs->wait( 'JID_000000000002', timeout => 0, interval => 0 ), undef, 'undef when the time is up' );
  ok( time - $t < 5, 'and it returned at once' );
  isa_ok( error_of { $running->jobs->wait( 'JID_000000000002', timeout => 'soon' ) }, 'WWW::iDRAC::Error::Validation', 'a timeout that is no number' );
  isa_ok( error_of { $running->jobs->wait( 'JID_000000000002', interval => -1 ) }, 'WWW::iDRAC::Error::Validation', 'a negative interval' );
  isa_ok( error_of { $running->jobs->wait( 'JID_000000000002', sleep => 1 ) }, 'WWW::iDRAC::Error::Validation', 'an unknown option' );
  isa_ok( error_of { $running->jobs->wait('x') }, 'WWW::iDRAC::Error::Validation', 'a bad id' );
};

subtest 'supports' => sub {
  my ($idrac) = setup();
  ok( $idrac->jobs->supports($_), $_ ) for qw( list get delete wait );
  my $off = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, ssh => 0 );
  ok( !$off->jobs->supports($_), 'ssh => 0: not '.$_ ) for qw( list get delete wait );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
