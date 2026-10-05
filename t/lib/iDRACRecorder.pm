package iDRACRecorder;

# Walks the Redfish tree of a controller with GET requests only and returns
# what it keeps of it as a map of path to document, the form FakeiDRAC serves.
#
#   my $recorder = iDRACRecorder->new( redfish => $redfish );
#   my $docs     = $recorder->record;
#
# Everything is walked, so that the summary can say what a controller has.
# Kept are only the kinds of document the tests read, told by @odata.type. A
# controller holds a great deal more, user names and SNMP communities among
# it, and what is not kept cannot end up in a public fixture.

use strict;
use warnings;

# what is not walked: the schema and message catalogues, which are large and
# say nothing about this controller, and everything about accounts, sessions
# and certificates
my $SKIP = qr{/(?:JSONSchemas|JsonSchemas|Registries|\$metadata|odata|AccountService|SessionService|Sessions|CertificateService|Certificates|Subscriptions)(?:/|\z)};

# the resource types that are kept
my %KEEP = map { $_ => 1 } qw(
  ServiceRoot
  ComputerSystemCollection ComputerSystem
  ProcessorCollection Processor
  MemoryCollection Memory
  EthernetInterfaceCollection EthernetInterface
  ChassisCollection Chassis Thermal Power
  ManagerCollection Manager
  LogServiceCollection LogService LogEntryCollection LogEntry
);

sub new {
  my ( $class, %arg ) = @_;
  return bless {
    redfish     => $arg{redfish},
    max_docs    => $arg{max_docs}    // 500,
    max_members => $arg{max_members} // 20,
    skipped     => [],
    failed      => {},
    walked      => {},
    truncated   => 0
  }, $class;
}

sub skipped   { $_[0]{skipped} }
sub failed    { $_[0]{failed} }
sub walked    { $_[0]{walked} }       # path => resource type, for everything that was fetched
sub truncated { $_[0]{truncated} }    # addresses still to walk when max_docs was reached

# the paths that were fetched and not kept
sub left_out {
  my ( $self ) = @_;
  return grep { !$KEEP{ $self->{walked}{$_} } } sort keys %{ $self->{walked} };
}

# "#ComputerSystem.v1_0_2.ComputerSystem" and the older
# "#ComputerSystem.1.0.0.ComputerSystem" are both a ComputerSystem
sub type_of {
  my ( $class, $doc ) = @_;
  my ( $type ) = ( $doc->{'@odata.type'} // '' ) =~ /\A#?([A-Za-z0-9]+)/;
  return $type // '(no type)';
}

sub key {
  my ( $class, $path ) = @_;
  $path =~ s/#.*\z//;
  $path =~ s{/+\z}{} unless $path eq '/';
  return $path;
}

# every address a document points to
sub links {
  my ( $class, $node ) = @_;
  return map { $class->links($_) } @$node if ref $node eq 'ARRAY';
  return () unless ref $node eq 'HASH';
  return map {
    my $value = $node->{$_};
    ref $value ? $class->links($value)
      : ( $_ eq '@odata.id' || $_ eq 'Members@odata.nextLink' ) && defined $value && $value =~ m{\A/redfish/v1(?:/|\z)} ? $value
      :                                                                                                                 ()
  } sort keys %$node;
}

# a long collection is cut to its first entries, and says so
sub trim {
  my ( $self, $doc ) = @_;
  my $members = $doc->{Members};
  return $doc unless ref $members eq 'ARRAY' && @$members > $self->{max_members};
  my %cut = ( %$doc, Members => [ @$members[ 0 .. $self->{max_members} - 1 ] ], 'Members@odata.count' => $self->{max_members} );
  delete $cut{'Members@odata.nextLink'};
  return \%cut;
}

sub record {
  my ( $self ) = @_;
  my ( %docs, %seen );
  my @queue = ('/redfish/v1/');
  while (@queue) {
    if ( keys %{ $self->{walked} } >= $self->{max_docs} ) { $self->{truncated} = grep { !$seen{ $self->key($_) } } @queue; last }
    my $key = $self->key( shift @queue );
    next if $seen{$key}++;
    if ( $key =~ $SKIP ) { push @{ $self->{skipped} }, $key; next }
    my $doc;
    if ( !eval { $doc = $self->{redfish}->get($key); 1 } ) { $self->{failed}{$key} = "$@"; next }
    next unless ref $doc eq 'HASH';
    $doc = $self->trim($doc);
    my $type = $self->{walked}{$key} = $self->type_of($doc);
    $docs{$key} = $doc if $KEEP{$type};
    # an entry that came whole inside its collection is not fetched once more
    $seen{ $self->key( $_->{'@odata.id'} ) }++
      for grep { ref $_ eq 'HASH' && keys %$_ > 1 && defined $_->{'@odata.id'} } ref $doc->{Members} eq 'ARRAY' ? @{ $doc->{Members} } : ();
    push @queue, $self->links($doc);
  }
  return \%docs;
}

1;
