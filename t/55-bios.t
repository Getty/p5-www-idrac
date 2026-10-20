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

# the value a call returns; an error of the library is in the diagnostics.
# A method the library does not have at all is a failed expectation, not a
# die that ends the file.
sub value_of (&) {
  my ( $code ) = @_;
  my $value;
  if ( eval { $value = $code->(); 1 } ) { return $value }
  diag( ref $@ ? "$@" : 'the call died instead of returning a value' );
  return;
}

sub setup {
  my ( %arg ) = @_;
  my $racadm = FakeRacadm->new(%arg);
  my $idrac  = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, racadm => $racadm->transport );
  return ( $idrac, $racadm );
}

subtest 'groups' => sub {
  my ( $idrac, $fake ) = setup();
  is_deeply( $idrac->bios->groups, [qw( BiosBootSettings ProcSettings SysProfileSettings )], 'the names' );
  is_deeply( $fake->commands, ['racadm get BIOS'], 'one command' );
  is_deeply( WWW::iDRAC::Bios->groups_from("A\r\nB\n\n  C  \n[x]\n"), [qw( A B C )], 'groups_from' );

  my ($old) = setup( lists_groups => 0 );
  my $e = error_of { $old->bios->groups };
  isa_ok( $e, 'WWW::iDRAC::Error::Unsupported', 'a controller that does not list them' );
  is( $e->capability, 'bios.groups', 'by name' );
  like( $e->reason, qr/does not list/, 'and why' );
  is_deeply( $old->bios->group('BiosBootSettings')->[0], { name => 'BootMode', value => 'Bios', read_only => 0 }, 'but serves a group by name' );

  # only the answer of an iDRAC 7 is a fact about the controller; another error is one
  my $racadm = FakeRacadm->new( replies => { 'racadm get BIOS' => "ERROR: RAC1021: The BIOS is busy.\n" } );
  my $busy   = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, racadm => $racadm->transport );
  $e = error_of { $busy->bios->groups };
  isa_ok( $e, 'WWW::iDRAC::Error::API', 'another error of racadm' );
  ok( $e && !$e->isa('WWW::iDRAC::Error::Unsupported'), 'is no Unsupported' );
  is( value_of { $e->message_id }, 'RAC1021', 'and keeps its code' );
};

subtest 'group and get' => sub {
  my ($idrac) = setup();
  my $group = $idrac->bios->group('ProcSettings');
  shape_ok( $group, 'bios.group' );
  is( ( grep { $_->{read_only} } @$group ), 2, 'two read-only entries' );
  is( $idrac->bios->get('BiosBootSettings.BootMode'), 'Bios', 'one value' );
  is( $idrac->bios->get('BiosBootSettings.HddSeq'), undef, 'an empty value is undef' );
  my $e = error_of { $idrac->bios->get('BiosBootSettings.Nope') };
  isa_ok( $e, 'WWW::iDRAC::Error::API', 'an attribute it does not have' );
  ok( $e->is_not_found, 'is a not found' );
  $e = error_of { $idrac->bios->group('NoSuchGroup') };
  ok( $e->is_not_found, 'so is a group' );
  for my $bad ( undef, '', 'a b', 'A.B', 'A;B', [], '../x' ) {
    isa_ok( error_of { $idrac->bios->group($bad) }, 'WWW::iDRAC::Error::Validation', 'group '.( $bad // 'undef' ) );
  }
  for my $bad ( undef, '', 'NoGroup', 'A.B.C', 'A. B', 'A.B;x', [] ) {
    isa_ok( error_of { $idrac->bios->get($bad) }, 'WWW::iDRAC::Error::Validation', 'name '.( $bad // 'undef' ) );
  }
};

subtest 'set stages and commit makes the job' => sub {
  my ( $idrac, $fake ) = setup();
  my $staged = $idrac->bios->set( 'BiosBootSettings.BootMode' => 'Uefi' );
  is_deeply( $staged, { name => 'BiosBootSettings.BootMode', value => 'Uefi', previous => 'Bios', fqdd => 'BIOS.Setup.1-1', pending => 1 }, 'what was staged' );
  is_deeply( $fake->commands, [ 'racadm get BIOS.BiosBootSettings.BootMode', 'racadm set BIOS.BiosBootSettings.BootMode Uefi' ], 'read first, then written' );
  is_deeply( $fake->staged, { 'BIOS.BiosBootSettings.BootMode' => 'Uefi' }, 'staged on the controller' );
  is( $idrac->bios->get('BiosBootSettings.BootMode'), 'Bios', 'the value now is still the old one' );
  is( scalar @{ $fake->jobs }, 0, 'and no job yet' );

  my $job = $idrac->bios->commit;
  is_deeply( $job, { job_id => 'JID_900000000001', reboot_job_id => undef, fqdd => 'BIOS.Setup.1-1' }, 'the commit job, no restart' );
  like( $fake->commands->[-1], qr/\Aracadm jobqueue create BIOS\.Setup\.1-1 -r none -s TIME_NOW\z/, 'asked for no restart explicitly' );
  is( $fake->jobs->[0]{status}, 'Scheduled', 'a scheduled job' );

  $job = $idrac->bios->commit( reboot => 'graceful' );
  is( $job->{reboot_job_id}, 'RID_900000000002', 'a restart job when asked for one' );
  like( $fake->commands->[-1], qr/ -r graceful /, 'the restart type' );

  for my $bad ( [ reboot => 'yes' ], [ reboot => 'none; reboot' ], [ reboot => [] ], [ now => 1 ] ) {
    isa_ok( error_of { $idrac->bios->commit(@$bad) }, 'WWW::iDRAC::Error::Validation', 'commit '.join '=', map { ref $_ ? 'ref' : $_ } @$bad );
  }
};

subtest 'set refuses before it writes' => sub {
  my ( $idrac, $fake ) = setup();
  my $e = error_of { $idrac->bios->set( 'ProcSettings.Proc1NumCores' => '8' ) };
  isa_ok( $e, 'WWW::iDRAC::Error::Validation', 'a read-only attribute' );
  like( "$e", qr/read-only/, 'says so' );
  isa_ok( error_of { $idrac->bios->set( 'BiosBootSettings.BootMode' => 'Bios; reboot' ) }, 'WWW::iDRAC::Error::Validation', 'a value with a semicolon' );
  isa_ok( error_of { $idrac->bios->set( 'BiosBootSettings.BootMode' => undef ) }, 'WWW::iDRAC::Error::Validation', 'no value' );
  isa_ok( error_of { $idrac->bios->set( 'BiosBootSettings.BootMode' => ['Bios'] ) }, 'WWW::iDRAC::Error::Validation', 'a reference' );
  isa_ok( error_of { $idrac->bios->set( 'Bios BootMode' => 'Bios' ) }, 'WWW::iDRAC::Error::Validation', 'a name with a space' );
  $e = error_of { $idrac->bios->set( 'BiosBootSettings.Nope' => 'x' ) };
  ok( $e->is_not_found, 'an attribute it does not have' );
  ok( !( grep { /\Aracadm set/ } @{ $fake->commands } ), 'no set was sent for any of them' );
  $e = error_of { $idrac->bios->set( 'BiosBootSettings.BootMode' => 'badvalue' ) };
  isa_ok( $e, 'WWW::iDRAC::Error::API', 'the BIOS refuses a value' );
  is( $e->message_id, 'RAC1052', 'with its code' );
  is_deeply( $fake->staged, {}, 'and nothing is staged' );
  is( WWW::iDRAC::Bios->pending_from("RAC1017: ... in pending state.\n"), 1, 'pending_from' );
  is( WWW::iDRAC::Bios->pending_from("done\n"), 0, 'and not pending' );
  is( WWW::iDRAC::Bios->pending_from(undef), 0, 'nothing' );
};

subtest 'set with a value that needs quotes' => sub {
  my ( $idrac, $fake ) = setup();
  $idrac->bios->set( 'BiosBootSettings.HddSeq' => 'RAID.Slot.2-1,Disk.Direct.0-0' );
  is( $fake->commands->[-1], 'racadm set BIOS.BiosBootSettings.HddSeq RAID.Slot.2-1,Disk.Direct.0-0', 'a list as it is' );
  $idrac->bios->set( 'BiosBootSettings.HddSeq' => '' );
  is( $fake->commands->[-1], 'racadm set BIOS.BiosBootSettings.HddSeq ""', 'empty is two quotes' );
};

subtest 'set refuses a value racadm would read as an option' => sub {
  my ( $idrac, $fake ) = setup();
  for my $value ( '-d', '-f' ) {
    isa_ok( error_of { $idrac->bios->set( 'BiosBootSettings.HddSeq' => $value ) }, 'WWW::iDRAC::Error::Validation', $value );
  }
  is_deeply( $fake->commands, [], 'before anything is sent' );
};

subtest 'a bad value sends nothing at all' => sub {
  my ( $idrac, $fake ) = setup();
  for my $value ( 'a"b', 'a;b', "a\nb", '$(x)', '-d', undef, [], 'x' x 513 ) {
    isa_ok( error_of { $idrac->bios->set( 'BiosBootSettings.HddSeq' => $value ) }, 'WWW::iDRAC::Error::Validation', 'value '.( ref $value || $value // 'undef' ) );
  }
  is_deeply( $fake->commands, [], 'no racadm get either, the value is judged first' );
  is_deeply( $fake->staged, {}, 'and nothing staged' );
};

subtest 'commit needs a job id in the answer' => sub {
  my $racadm = FakeRacadm->new( replies => {
    'racadm get BIOS.BiosBootSettings'                          => "[Key=BIOS.Setup.1-1#BiosBootSettings]\nBootMode=Bios\n",
    'racadm jobqueue create BIOS.Setup.1-1 -r none -s TIME_NOW' => "RAC1024: Successfully scheduled a job.\n"
  } );
  my $idrac = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, racadm => $racadm->transport );
  my $e = error_of { $idrac->bios->commit };
  isa_ok( $e, 'WWW::iDRAC::Error::API', 'an answer without JID_' );
  like( $e ? "$e" : 'no error at all', qr/no job/i, 'says so' );
  ok( !WWW::iDRAC::Bios->can('fqdd'), 'the component name is read inside, no method of the area' );
  isa_ok( error_of { $idrac->bios->supports('fqdd') }, 'WWW::iDRAC::Error::Validation', 'and no capability' );
};

subtest 'job_from' => sub {
  is_deeply( WWW::iDRAC::Bios->job_from( "RAC1024: Successfully scheduled a job.\nCommit JID = JID_123456789012\nReboot JID = RID_123456789013\n", 'BIOS.Setup.1-1' ),
    { job_id => 'JID_123456789012', reboot_job_id => 'RID_123456789013', fqdd => 'BIOS.Setup.1-1' }, 'both' );
  is_deeply( WWW::iDRAC::Bios->job_from( "nothing\n", 'F' ), { job_id => undef, reboot_job_id => undef, fqdd => 'F' }, 'none' );
};

subtest 'supports' => sub {
  my ($idrac) = setup();
  ok( $idrac->bios->supports($_), $_ ) for qw( groups group get set commit );
  # a BIOS that shows nothing writable
  my $racadm = FakeRacadm->new( replies => { 'racadm get BIOS.BiosBootSettings' => "[Key=BIOS.Setup.1-1#BiosBootSettings]\n#BootMode=Bios\n" } );
  my $only = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, racadm => $racadm->transport );
  ok( !$only->bios->supports('set'), 'not set when nothing is writable' );
  ok( !$only->bios->supports('commit'), 'nor commit' );
  isa_ok( error_of { $idrac->bios->supports('explode') }, 'WWW::iDRAC::Error::Validation', 'unknown' );
};

subtest 'racadm switched off or not there' => sub {
  my $idrac = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, ssh => 0 );
  my $e = error_of { $idrac->bios->get('BiosBootSettings.BootMode') };
  isa_ok( $e, 'WWW::iDRAC::Error::Unsupported', 'ssh => 0' );
  is( $e->capability, 'bios.get', 'the method' );
  like( $e->reason, qr/switched off \(ssh => 0\)/, 'and the reason' );
  ok( !$idrac->has_racadm || !$idrac->racadm->connected, 'nothing was connected' );

  my $refused = FakeRacadm->new( fail => WWW::iDRAC::Error::Network->new( message => 'connecting failed: Connection refused', cause => 'refused' ) );
  my $off = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, racadm => $refused->transport );
  $e = error_of { $off->bios->groups };
  isa_ok( $e, 'WWW::iDRAC::Error::Unsupported', 'nothing on the SSH port' );
  like( $e->reason, qr/SSH port/, 'with the reason' );
  ok( !$off->bios->supports('groups'), 'and supports says no' );

  my $auth = FakeRacadm->new( fail => WWW::iDRAC::Error::Network->new( message => 'Permission denied', cause => 'auth' ) );
  my $bad = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, racadm => $auth->transport );
  isa_ok( error_of { $bad->bios->groups }, 'WWW::iDRAC::Error::Network', 'a refused login stays a network error' );
  isa_ok( error_of { $bad->bios->supports('groups') }, 'WWW::iDRAC::Error::Network', 'also for supports' );

  for my $cause (qw( timeout host_key other )) {
    my $broken = FakeRacadm->new( fail => WWW::iDRAC::Error::Network->new( message => 'broken', cause => $cause ) );
    my $idrac2 = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, racadm => $broken->transport );
    my $e = error_of { $idrac2->bios->groups };
    isa_ok( $e, 'WWW::iDRAC::Error::Network', 'cause '.$cause.' stays a network error' );
    is( $e && $e->cause, $cause, 'with its cause' );
    ok( !( $e && $e->isa('WWW::iDRAC::Error::Unsupported') ), 'and is no Unsupported' );
  }

  my $away = FakeRacadm->new( fail => WWW::iDRAC::Error::Network->new( message => 'ssh: connect to host idrac.test port 22: No route to host', cause => 'unreachable' ) );
  my $far  = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, racadm => $away->transport );
  isa_ok( error_of { $far->bios->groups }, 'WWW::iDRAC::Error::Network', 'an unreachable controller stays a network error' );
  isa_ok( error_of { $far->bios->supports('groups') }, 'WWW::iDRAC::Error::Network', 'also for supports' );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
