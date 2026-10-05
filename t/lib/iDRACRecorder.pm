package iDRACRecorder;

# Walks the Redfish tree of a controller with GET requests only and returns
# what it found as a map of path to document, the form FakeiDRAC serves.
#
#   my $docs = iDRACRecorder->new( redfish => $redfish )->record;

use strict;
use warnings;

# what is not walked: the schema and message catalogues, which are large and
# say nothing about this controller, and everything about accounts, sessions
# and certificates
my $SKIP = qr{/(?:JSONSchemas|JsonSchemas|Registries|\$metadata|odata|AccountService|SessionService|Sessions|CertificateService|Certificates|Subscriptions)(?:/|\z)};

sub new {
  my ( $class, %arg ) = @_;
  return bless {
    redfish     => $arg{redfish},
    max_docs    => $arg{max_docs}    // 500,
    max_members => $arg{max_members} // 20,
    skipped     => [],
    failed      => {}
  }, $class;
}

sub skipped { $_[0]{skipped} }
sub failed  { $_[0]{failed} }

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
  while ( @queue && keys %docs < $self->{max_docs} ) {
    my $key = $self->key( shift @queue );
    next if $seen{$key}++;
    if ( $key =~ $SKIP ) { push @{ $self->{skipped} }, $key; next }
    my $doc;
    if ( !eval { $doc = $self->{redfish}->get($key); 1 } ) { $self->{failed}{$key} = "$@"; next }
    next unless ref $doc eq 'HASH';
    $docs{$key} = $self->trim($doc);
    # an entry that came whole inside its collection is not fetched once more
    $seen{ $self->key( $_->{'@odata.id'} ) }++
      for grep { ref $_ eq 'HASH' && keys %$_ > 1 && defined $_->{'@odata.id'} } ref $docs{$key}{Members} eq 'ARRAY' ? @{ $docs{$key}{Members} } : ();
    push @queue, $self->links( $docs{$key} );
  }
  return \%docs;
}

1;
