#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

# What WWW::iDRAC::Racadm and ::Racadm::SSH do without any I/O: quoting, the
# command line, errors and blocks in the text racadm prints, the options of
# the SSH client. The texts have the forms the controllers printed on
# 2026-10-14 (see t/fixtures/), with invented values.

use WWW::iDRAC::Racadm;
use WWW::iDRAC::Racadm::SSH;

my $R   = 'WWW::iDRAC::Racadm';
my $SSH = 'WWW::iDRAC::Racadm::SSH';

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

subtest 'quote' => sub {
  is( $R->quote('BIOS.BiosBootSettings.BootMode'), 'BIOS.BiosBootSettings.BootMode', 'a plain name as it is' );
  is( $R->quote('//host/share/a.iso'), '//host/share/a.iso', 'a share' );
  is( $R->quote('-c'), '-c', 'an option' );
  is( $R->quote('NIC.Integrated.1-1-1,NIC.Slot.6-2'), 'NIC.Integrated.1-1-1,NIC.Slot.6-2', 'a list' );
  is( $R->quote('my share'), '"my share"', 'a space gets quotes' );
  is( $R->quote(''), '""', 'empty is two quotes' );
  is( $R->quote('#1'), '"#1"', 'a leading # is quoted' );
  for my $bad ( 'a"b', 'a\\b', 'a`b', 'a$b', 'a;b', 'a|b', 'a&b', 'a<b', 'a>b', "a\nb", "a\tb", 'a(b', 'a*b', 'a!b', "a'b", "\x{e4}", 'a~b' ) {
    my $e = error_of { $R->quote($bad) };
    isa_ok( $e, 'WWW::iDRAC::Error::Validation', 'refused: '.join '', map { sprintf '%%%02X', ord } split //, $bad );
    unlike( "$e", qr/\Q$bad\E/, 'and the message does not carry it' ) if length $bad > 1;
  }
  isa_ok( error_of { $R->quote(undef) }, 'WWW::iDRAC::Error::Validation', 'undef' );
  isa_ok( error_of { $R->quote( [] ) }, 'WWW::iDRAC::Error::Validation', 'a reference' );
  isa_ok( error_of { $R->quote( 'a' x 513 ) }, 'WWW::iDRAC::Error::Validation', 'too long' );
};

subtest 'command_from' => sub {
  is( $R->command_from( get => 'BIOS.BiosBootSettings' ), 'racadm get BIOS.BiosBootSettings', 'get' );
  is( $R->command_from( qw( jobqueue view -i JID_123456789012 ) ), 'racadm jobqueue view -i JID_123456789012', 'jobqueue' );
  is( $R->command_from( set => 'BIOS.A.B', 'a value' ), 'racadm set BIOS.A.B "a value"', 'a value with a space' );
  isa_ok( error_of { $R->command_from() }, 'WWW::iDRAC::Error::Validation', 'no subcommand' );
  isa_ok( error_of { $R->command_from( get => 'BIOS.A; reboot' ) }, 'WWW::iDRAC::Error::Validation', 'an injected command' );
  isa_ok( error_of { $R->command_from( get => "BIOS\nracadm serveraction powerdown" ) }, 'WWW::iDRAC::Error::Validation', 'an injected line' );
};

subtest 'text_from' => sub {
  is( $R->text_from("a\r\nb\r\n"), "a\nb\n", 'no carriage returns' );
  is( $R->text_from(undef), '', 'nothing is empty' );
};

subtest 'error_from' => sub {
  is( $R->error_from("[Key=BIOS.Setup.1-1#BiosBootSettings]\nBootMode=Uefi\n"), undef, 'no error in a block' );
  is( $R->error_from(''), undef, 'none in nothing' );
  is( $R->error_from("RAC1017: Successfully modified the object value and the change is in pending state.\n"), undef, 'a success with a code is none' );
  is( $R->error_from("RAC1024: Successfully scheduled a job.\nCommit JID = JID_000000000001\n"), undef, 'nor is a job created' );
  is( $R->error_from("Remote File Share is Disabled\nUserName \n"), undef, 'nor a status' );

  my $e = $R->error_from("ERROR: RAC1019: The specified object is not supported for the current system \n       configuration.\n       Verify the object dependency using \"racadm help <device \n       class>.<groupname>.<objectname>\", and retry the operation.\n");
  is( $e->{code}, 'RAC1019', 'the code' );
  like( $e->{message}, qr/\AThe specified object is not supported for the current system configuration\. Verify the object dependency/, 'the message, one line' );
  is( $e->{license}, undef, 'no license' );

  $e = $R->error_from("ERROR: SWC0242 : A required license is missing or expired.\n       Obtain an appropriate license and try again, or contact your service\n       provider for additional details.\nRequired License -- Virtual Media\n");
  is( $e->{code}, 'SWC0242', 'a code with a space before the colon' );
  is( $e->{license}, 'Virtual Media', 'the license it names' );
  unlike( $e->{message}, qr/Required License/, 'which is not part of the message' );

  $e = $R->error_from("ERROR: Unable to perform requested operation.\n");
  is( $e->{code}, undef, 'an error without a code' );
  is( $e->{message}, 'Unable to perform requested operation.', 'and its message' );

  $e = $R->error_from("RAC992: Invalid job: JID_000000000001.\n       To monitor the current set of the jobs, use the \"racadm jobqueue \n       view\" command.\n");
  is( $e->{code}, 'RAC992', 'a coded line that says invalid' );
  like( $e->{message}, qr/\AInvalid job: JID_000000000001\. To monitor/, 'with its text' );

  is( $R->error_from("\n\nERROR: RAC917 : bad\n")->{code}, 'RAC917', 'leading blank lines' );
  is( $R->error_from("ERROR: RAC917 : bad\r\n")->{message}, 'bad', 'and carriage returns' );
};

subtest 'blocks_from' => sub {
  my @blocks = $R->blocks_from( <<'TEXT' );
[Key=BIOS.Setup.1-1#ProcSettings]
DcuIpPrefetcher=Enabled
#Proc1Brand=[Intel(R) Xeon(R) CPU E3-1220 v6 @ 3.00GHz       ]
#Proc1NumCores=4
HddSeq=
UefiBootSeq=Unknown.Integrated.1-1,,,,NIC.Slot.6-1
TEXT
  is( scalar @blocks, 1, 'one block' );
  is_deeply( [ @{ $blocks[0] }{qw( kind id )} ], [ 'Key', 'BIOS.Setup.1-1#ProcSettings' ], 'kind and id' );
  is_deeply( $blocks[0]{entries}, [
    { name => 'DcuIpPrefetcher', value => 'Enabled',                                  read_only => 0 },
    { name => 'Proc1Brand',      value => 'Intel(R) Xeon(R) CPU E3-1220 v6 @ 3.00GHz', read_only => 1 },
    { name => 'Proc1NumCores',   value => '4',                                         read_only => 1 },
    { name => 'HddSeq',          value => '',                                          read_only => 0 },
    { name => 'UefiBootSeq',     value => 'Unknown.Integrated.1-1,,,,NIC.Slot.6-1',   read_only => 0 }
  ], 'entries: # is read-only, brackets and their padding go' );

  @blocks = $R->blocks_from( <<'TEXT' );
-------------------------JOB QUEUE------------------------
[Job ID=JID_000000000001]
Job Name=ConfigBIOS:BIOS.Setup.1-1
Status=Scheduled
Start Time=[TIME_NOW]
Message=[JCP001: Task successfully scheduled.]
[Job ID=RID_000000000002]
Job Name=Reboot
----------------------------------------------------------
TEXT
  is_deeply( [ map { $_->{kind}.'='.$_->{id} } @blocks ], [ 'Job ID=JID_000000000001', 'Job ID=RID_000000000002' ], 'job blocks' );
  is( $blocks[0]{entries}[3]{value}, 'JCP001: Task successfully scheduled.', 'a value with a colon' );
  is_deeply( [ $R->blocks_from("ERROR: nope\n") ], [], 'no blocks in an error' );
  is_deeply( [ $R->blocks_from(undef) ], [], 'nor in nothing' );
};

subtest 'the options of the SSH client' => sub {
  my $pairs = sub { my @o = @{ $_[0] }; my @s; while (@o) { shift @o eq '-o' or die 'not -o'; push @s, shift @o } @s };
  my @default = $pairs->( $SSH->options_from( verify_host_key => 1 ) );
  ok( ( grep { $_ eq 'StrictHostKeyChecking=yes' } @default ), 'strict by default' );
  ok( !( grep { /StrictHostKeyChecking=no/ } @default ), 'and not off' );
  ok( ( grep { $_ eq 'NumberOfPasswordPrompts=1' } @default ), 'one password attempt' );
  ok( ( grep { $_ eq 'PubkeyAuthentication=no' } @default ), 'password login only' );
  ok( !( grep { /UserKnownHostsFile/ } @default ), 'the known_hosts of the user' );

  my @file = $pairs->( $SSH->options_from( verify_host_key => 1, known_hosts => '/etc/idrac_hosts' ) );
  ok( ( grep { $_ eq 'UserKnownHostsFile=/etc/idrac_hosts' } @file ), 'a known_hosts file' );
  ok( ( grep { $_ eq 'StrictHostKeyChecking=yes' } @file ), 'still strict' );

  my @pinned = $pairs->( $SSH->options_from( verify_host_key => 1, key_file => '/tmp/pin' ) );
  ok( ( grep { $_ eq 'UserKnownHostsFile=/tmp/pin' } @pinned ) && ( grep { $_ eq 'GlobalKnownHostsFile=/dev/null' } @pinned ), 'a pinned key is all that counts' );

  my @open = $pairs->( $SSH->options_from( verify_host_key => 0 ) );
  ok( ( grep { $_ eq 'StrictHostKeyChecking=no' } @open ) && ( grep { $_ eq 'UserKnownHostsFile=/dev/null' } @open ), 'off only when asked' );

  my @extra = $pairs->( $SSH->options_from( verify_host_key => 1, ssh_opts => ['KexAlgorithms=+diffie-hellman-group14-sha1'] ) );
  is( $extra[-1], 'KexAlgorithms=+diffie-hellman-group14-sha1', 'extra options come last, so they cannot override' );
  is( ( grep { /StrictHostKeyChecking/ } @extra ), 1, 'and there is one strictness' );
  isa_ok( error_of { $SSH->options_from( verify_host_key => 1, ssh_opts => ['ProxyCommand=nc -x evil %h %p'] ) }, 'WWW::iDRAC::Error::Validation', 'no spaces' );
  isa_ok( error_of { $SSH->options_from( verify_host_key => 1, ssh_opts => ['not-an-option'] ) }, 'WWW::iDRAC::Error::Validation', 'Name=value' );
};

subtest 'known_hosts_line_from' => sub {
  is( $SSH->known_hosts_line_from( 'idrac.example.org', 22, 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq' ), "idrac.example.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq\n", 'port 22 is the bare name' );
  is( $SSH->known_hosts_line_from( 'idrac.example.org', 2222, 'ssh-rsa AAAAB3NzaC1yc2E= comment' ), "[idrac.example.org]:2222 ssh-rsa AAAAB3NzaC1yc2E=\n", 'another port in brackets, no comment' );
  isa_ok( error_of { $SSH->known_hosts_line_from( 'h', 22, 'nonsense' ) }, 'WWW::iDRAC::Error::Validation', 'one word' );
  isa_ok( error_of { $SSH->known_hosts_line_from( 'h', 22, "ssh-rsa AAAA\nother.host ssh-rsa BBBB" ) }, 'WWW::iDRAC::Error::Validation', 'no second line' );
  isa_ok( error_of { $SSH->known_hosts_line_from( 'h', 22, undef ) }, 'WWW::iDRAC::Error::Validation', 'undef' );
};

subtest 'cause_from' => sub {
  my %want = (
    'ssh: connect to host 192.0.2.1 port 22: Connection refused'                                 => 'refused',
    'ssh: Could not resolve hostname idrac.test: Name or service not known'                      => 'refused',
    'Host key verification failed.'                                                              => 'host_key',
    'WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!'                                           => 'host_key',
    'Permission denied (publickey,keyboard-interactive).'                                        => 'auth',
    'bad password'                                                                               => 'auth',
    'command timed out'                                                                          => 'timeout',
    'something else'                                                                             => 'other'
  );
  is( $SSH->cause_from($_), $want{$_}, $_ ) for sort keys %want;
  is( $SSH->cause_from(undef), 'other', 'undef' );
};

done_testing;
