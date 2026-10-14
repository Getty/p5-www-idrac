package FakeRacadm;

# An in-memory stand-in for the SSH side of an iDRAC, used as the runner of
# WWW::iDRAC::Racadm in the tests: it is handed the command line and returns
# what racadm would have printed.
#
#   my $fake  = FakeRacadm->new;                                          # the invented controller below
#   my $fake  = FakeRacadm->from_file('t/fixtures/idrac8/racadm.json');   # a recorded one
#   my $idrac = WWW::iDRAC->new( ..., racadm => $fake->transport );
#
# The texts have the form of what a real iDRAC 7 and 8 printed on 2026-10-14
# (see t/fixtures/): [Key=...] blocks, #name for read-only, [Job ID=...]
# blocks, ERROR: lines with an exit status that is not looked at. The values
# are invented. A recording is a map of the command line to the text; a
# command that is not in it dies, so a test notices a command nobody
# recorded.
#
# Without a recording the fake keeps a little state, so that the writing
# methods can be tried: set stages a value, jobqueue create makes a job of
# the staged values, jobqueue delete removes one, remoteimage connects.

use strict;
use warnings;
use JSON::MaybeXS;
use WWW::iDRAC::Error::Network;
use WWW::iDRAC::Racadm;

my $JSON = JSON::MaybeXS->new( utf8 => 1, canonical => 1 );

sub new {
  my ( $class, %arg ) = @_;
  return bless {
    replies   => $arg{replies},
    commands  => [],
    connected => 0,
    timeouts  => [],
    licensed  => exists $arg{licensed} ? $arg{licensed} : 1,
    license   => $arg{license} // 'iDRAC8 Enterprise License',
    fail      => $arg{fail},
    bios      => {
      BiosBootSettings => [ [ BootMode => 'Bios', 0 ], [ BootSeqRetry => 'Disabled', 0 ], [ HddSeq => '', 0 ], [ SetBootOrderFqdd1 => '', 0 ] ],
      ProcSettings     => [ [ LogicalProc => 'Enabled', 0 ], [ ProcCores => 'All', 0 ], [ Proc1Brand => '[Intel(R) Xeon(R) CPU E3-1220 v6 @ 3.00GHz]', 1 ], [ Proc1NumCores => '4', 1 ] ],
      SysProfileSettings => [ [ SysProfile => 'PerfOptimized', 0 ] ]
    },
    lists_groups => exists $arg{lists_groups} ? $arg{lists_groups} : 1,
    staged       => {},
    jobs         => $arg{jobs} || [],
    next_job     => 1,
    remote       => { connected => 0, user => '', share => '' },
    config       => { Attached => 'AutoAttach', BootOnce => 'Disabled', Enable => 'Enabled' }
  }, $class;
}

sub from_file {
  my ( $class, $file, %arg ) = @_;
  open my $fh, '<:raw', $file or die 'cannot read '.$file.': '.$!;
  return $class->new( %arg, replies => $JSON->decode( do { local $/; <$fh> } ) );
}

sub commands  { $_[0]{commands} }
sub timeouts  { $_[0]{timeouts} }
sub jobs      { $_[0]{jobs} }
sub staged    { $_[0]{staged} }
sub remote    { $_[0]{remote} }
sub connected { $_[0]{connected} }

sub disconnect {
  my ( $self ) = @_;
  my $was = $self->{connected};
  $self->{connected} = 0;
  return $was ? 1 : 0;
}

# the Racadm transport that runs on this fake
sub transport {
  my ( $self, %arg ) = @_;
  return WWW::iDRAC::Racadm->new( host => 'idrac.test', username => 'root', password => 'calvin', runner => $self, %arg );
}

# the command line as words, quotes undone
sub _words { my ( $line ) = @_; return map { defined $_->[0] ? $_->[0] : $_->[1] } map { [ $_ =~ /\A"(.*)"\z/ ? $1 : undef, $_ ] } $line =~ /("[^"]*"|\S+)/g }

sub run {
  my ( $self, $command, $timeout ) = @_;
  push @{ $self->{commands} }, $command;
  push @{ $self->{timeouts} }, $timeout;
  if ( my $fail = $self->{fail} ) {
    $self->{connected} = 0;
    die ref $fail eq 'CODE' ? $fail->($command) : $fail;
  }
  $self->{connected} = 1;
  if ( $self->{replies} ) {
    die "FakeRacadm: nothing recorded for: $command\n" unless exists $self->{replies}{$command};
    my $reply = $self->{replies}{$command};
    return ref $reply eq 'CODE' ? $reply->($command) : $reply;
  }
  my ( undef, $sub, @arg ) = _words($command);
  return "ERROR: Invalid subcommand specified.\n" unless defined $sub;
  my $handler = $self->can( '_do_'.$sub ) or return "ERROR: Invalid subcommand specified.\n";
  return $self->$handler(@arg);
}

sub _error_syntax { "ERROR: RAC917 : The syntax of the specified command is not correct.\n       See the command help text. To see the help text, run\n       \"racadm help <subcommand>\"\n" }

sub _do_getversion {
  return " Bios Version                     = 2.4.3\n\n iDRAC Version                    = 2.50.50.50\n\n Lifecycle Controller Version     = 2.50.50.50\n\n IDSDM Version                    = NA\n\n";
}

sub _do_license {
  my ( $self, $sub ) = @_;
  return _error_syntax() unless ( $sub // '' ) eq 'view';
  return "iDRAC.Embedded.1\n\tStatus               = OK\n\tDevice               = iDRAC.Embedded.1\n\tDevice Description   = iDRAC8\n\tUnique Identifier    = TAG0001\n\t\tLicense #1\n\t\t\tStatus               = OK\n\t\t\tTransaction ID       = 2\n\t\t\tLicense Description  = ".$self->{license}."\n\t\t\tLicense Type         = PERPETUAL\n\t\t\tEntitlement ID       = FD00000000000001\n\t\t\tLicense Bound        = TAG0001\n\t\t\tExpiration           = Not Applicable\n";
}

sub _group_text {
  my ( $self, $group ) = @_;
  my $entries = $self->{bios}{$group} or return undef;
  return "[Key=BIOS.Setup.1-1#$group]\n".join( '', map { ( $_->[2] ? '#' : '' ).$_->[0].'='.$_->[1]."\n" } @$entries );
}

sub _do_get {
  my ( $self, $name ) = @_;
  return _error_syntax() unless defined $name;
  if ( $name eq 'BIOS' ) {
    return "ERROR: Unable to perform requested operation.\n" unless $self->{lists_groups};
    return join '', map { "$_\n" } sort keys %{ $self->{bios} };
  }
  if ( $name eq 'iDRAC.VirtualMedia' ) {
    return "ERROR: SWC0242 : A required license is missing or expired.\n       Obtain an appropriate license and try again, or contact your service\n       provider for additional details.\nRequired License -- Virtual Media\n"
      unless $self->{licensed};
    my $c = $self->{config};
    return "[Key=iDRAC.Embedded.1#VirtualMedia.1]\nAttached=$c->{Attached}\nBootOnce=$c->{BootOnce}\nEnable=$c->{Enable}\n";
  }
  my ( $group, $attribute ) = $name =~ /\ABIOS\.([A-Za-z0-9]+)(?:\.([A-Za-z0-9]+))?\z/ or return "ERROR: RAC1019: The specified object is not supported for the current system \n       configuration.\n";
  my $text = $self->_group_text($group) // return "ERROR: RAC1020: No objects are available under the specified group for the \n       current system configuration.\n";
  return $text unless defined $attribute;
  my ($entry) = grep { $_->[0] eq $attribute } @{ $self->{bios}{$group} };
  return "ERROR: RAC1019: The specified object is not supported for the current system \n       configuration.\n" unless $entry;
  return "[Key=BIOS.Setup.1-1#$group]\n".( $entry->[2] ? '#' : '' ).$entry->[0].'='.$entry->[1]."\n";
}

sub _do_set {
  my ( $self, $name, $value ) = @_;
  return _error_syntax() unless defined $name && defined $value;
  my ( $group, $attribute ) = $name =~ /\ABIOS\.([A-Za-z0-9]+)\.([A-Za-z0-9]+)\z/ or return "ERROR: RAC1019: The specified object is not supported for the current system \n       configuration.\n";
  my ($entry) = grep { $_->[0] eq $attribute } @{ $self->{bios}{$group} || [] };
  return "ERROR: RAC1019: The specified object is not supported for the current system \n       configuration.\n" unless $entry;
  return "ERROR: RAC1051: The object is read-only.\n" if $entry->[2];
  return "ERROR: RAC1052: The value is not allowed for this object.\n" if $value =~ /\Abad/i;
  $self->{staged}{$name} = $value;
  return "[Key=BIOS.Setup.1-1#$group]\nRAC1017: Successfully modified the object value and the change is in pending state.\nTo apply modified value, create a configuration job and reboot the system.\n";
}

sub _job_text {
  my ( $job ) = @_;
  return "[Job ID=$job->{id}]\nJob Name=$job->{name}\nStatus=$job->{status}\nStart Time=[$job->{start}]\nExpiration Time=[Not Applicable]\nMessage=[$job->{message}]\nPercent Complete=[$job->{percent}]\n";
}

sub _do_jobqueue {
  my ( $self, $sub, @arg ) = @_;
  return _error_syntax() unless defined $sub;
  if ( $sub eq 'view' ) {
    if ( @arg && $arg[0] eq '-i' ) {
      my ($job) = grep { $_->{id} eq ( $arg[1] // '' ) } @{ $self->{jobs} };
      return "RAC992: Invalid job: ".( $arg[1] // '' ).".\n       To monitor the current set of the jobs, use the \"racadm jobqueue \n       view\" command.\n" unless $job;
      return "---------------------------- JOB -------------------------\n"._job_text($job)."----------------------------------------------------------\n";
    }
    return "-------------------------JOB QUEUE------------------------\n".join( '', map { _job_text($_) } @{ $self->{jobs} } )."----------------------------------------------------------\n";
  }
  if ( $sub eq 'delete' ) {
    return _error_syntax() unless @arg == 2 && $arg[0] eq '-i';
    my ($job) = grep { $_->{id} eq $arg[1] } @{ $self->{jobs} };
    return "RAC992: Invalid job: $arg[1].\n" unless $job;
    return "ERROR: RAC1033: The job is running and cannot be deleted.\n" if $job->{status} eq 'Running';
    @{ $self->{jobs} } = grep { $_->{id} ne $arg[1] } @{ $self->{jobs} };
    return "RAC1032: Successfully deleted the job $arg[1].\n";
  }
  if ( $sub eq 'create' ) {
    my ( $fqdd, %opt ) = @arg;
    return "ERROR: RAC1022: The component is not valid.\n" unless ( $fqdd // '' ) eq 'BIOS.Setup.1-1';
    my $n    = $self->{next_job}++;
    my $id   = sprintf 'JID_%012d', 900000000000 + $n;
    my $text = "RAC1024: Successfully scheduled a job.\nVerify the job status using \"racadm jobqueue view -i $id\" command.\nCommit JID = $id\n";
    push @{ $self->{jobs} }, { id => $id, name => 'ConfigBIOS:'.$fqdd, status => 'Scheduled', start => 'TIME_NOW', message => 'JCP001: Task successfully scheduled.', percent => 0 };
    if ( ( $opt{'-r'} // 'none' ) ne 'none' ) {
      my $rid = sprintf 'RID_%012d', 900000000000 + $n;
      push @{ $self->{jobs} }, { id => $rid, name => 'Reboot', status => 'Scheduled', start => 'TIME_NOW', message => 'JCP001: Task successfully scheduled.', percent => 0 };
      $text .= "Reboot JID = $rid\n";
    }
    $self->{staged} = {};
    return $text;
  }
  return _error_syntax();
}

sub _remote_text {
  my ( $self ) = @_;
  my $r = $self->{remote};
  return 'Remote File Share is '.( $r->{connected} ? 'Enabled' : 'Disabled' )."\nUserName $r->{user}\nPassword \nShareName $r->{share}\n";
}

sub _do_remoteimage {
  my ( $self, @arg ) = @_;
  return $self->_remote_text if @arg == 1 && $arg[0] eq '-s';
  return _error_syntax() unless @arg;
  if ( $arg[0] eq '-d' ) {
    $self->{remote} = { connected => 0, user => '', share => '' };
    return "Disconnect Remote Image is successful.\n";
  }
  if ( $arg[0] eq '-c' ) {
    my %opt = @arg[ 1 .. $#arg ];
    return "ERROR: SWC0242 : A required license is missing or expired.\nRequired License -- Remote File Share\n" unless $self->{licensed};
    return "ERROR: RAC1100: The location is not valid.\n" unless defined $opt{'-l'};
    $self->{remote} = { connected => 1, user => $opt{'-u'} // '', share => $opt{'-l'}, password => $opt{'-p'} };
    return "Remote Image is now configured\n";
  }
  return _error_syntax();
}

1;
