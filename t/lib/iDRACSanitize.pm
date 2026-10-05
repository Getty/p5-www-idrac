package iDRACSanitize;

# Takes what identifies a machine or a network out of recorded Redfish
# documents, before they are written to t/fixtures/. The repository is
# public; a recording that was not through here is not committed.
#
#   my $clean = iDRACSanitize->new->hide( host => 'idrac.lan' )->sanitize( \%docs );
#
# Three passes over the documents, which are a map of path to document:
#
#   1. the values of the keys in %BY_KEY are collected, each gets a
#      placeholder, and the same value gets the same placeholder everywhere
#   2. every string is rewritten: a collected value becomes its placeholder,
#      MAC and IP addresses become addresses from the documentation ranges
#   3. leaks() looks for values that must not be in the result
#
# Structural strings are left alone: keys, @odata values and action targets.

use strict;
use warnings;
use Socket qw( AF_INET6 inet_pton );

# key => the kind of placeholder its value gets
my %BY_KEY = (
  SerialNumber          => 'serial',
  SKU                   => 'tag',
  ServiceTag            => 'tag',
  ChassisServiceTag     => 'tag',
  NodeID                => 'tag',
  ExpressServiceCode    => 'code',
  AssetTag              => 'asset',
  UUID                  => 'uuid',
  ServiceEntryPointUUID => 'uuid',
  HostName              => 'host',
  FQDN                  => 'fqdn',
  DNSRacName            => 'host',
  DNSDomainName         => 'domain',
  UserName              => 'user'
);

my %FORMAT = (
  serial => sub { sprintf 'SERIAL%04d', $_[0] },
  tag    => sub { sprintf 'TAG%04d', $_[0] },
  code   => sub { sprintf '%011d', $_[0] },
  asset  => sub { sprintf 'ASSET%04d', $_[0] },
  uuid   => sub { sprintf '00000000-0000-0000-0000-%012d', $_[0] },
  host   => sub { sprintf 'host-%d', $_[0] },
  fqdn   => sub { sprintf 'fqdn-%d.example.org', $_[0] },
  domain => sub { sprintf 'example-%d.org', $_[0] },
  user   => sub { sprintf 'user-%d', $_[0] },
  mac    => sub { sprintf '00:00:5E:00:53:%02X', $_[0] % 256 },
  ipv4   => sub { sprintf '192.0.2.%d', $_[0] % 256 },
  ipv6   => sub { sprintf '2001:db8::%x', $_[0] }
);

sub new { bless { map => {}, count => {} }, $_[0] }

# the placeholder of a value, the same one each time
sub placeholder {
  my ( $self, $kind, $value ) = @_;
  return $self->{map}{$value} //= $FORMAT{$kind}->( ++$self->{count}{$kind} );
}

# a value known from outside the documents, the address the recording was made at for example
sub hide {
  my ( $self, $kind, $value ) = @_;
  $self->placeholder( $kind, $value ) if defined $value && length $value;
  return $self;
}

sub _walk {
  my ( $self, $node, $key, $visit ) = @_;
  # in the order of the keys, so that the same recording gets the same placeholders each time
  if ( ref $node eq 'HASH' ) { return { map { $_ => $self->_walk( $node->{$_}, $_, $visit ) } sort keys %$node } }
  if ( ref $node eq 'ARRAY' ) { return [ map { $self->_walk( $_, $key, $visit ) } @$node ] }
  return $node if ref $node || !defined $node;
  return $visit->( $node, $key );
}

sub _structural { $_[0] =~ /\A\@odata\.|\@odata\.|\Atarget\z/ }

sub _addresses {
  my ( $self, $text, $key ) = @_;
  $text =~ s{\b((?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2})\b}{ $self->placeholder( mac => uc $1 ) }ge;
  # a firmware version has the form of an IPv4 address
  $text =~ s{(?<![0-9.])((?:[0-9]{1,3}\.){3}[0-9]{1,3})(?![0-9]|\.[0-9])}{ $self->_ipv4($1) }ge unless $key =~ /version|firmware/i;
  $text =~ s{(?<![0-9A-Za-z:])([0-9A-Fa-f:]{2,39})(?![0-9A-Za-z:])}{ $self->_ipv6($1) }ge;
  return $text;
}

sub _ipv4 {
  my ( $self, $address ) = @_;
  return $address if grep { $_ > 255 } split /\./, $address;
  # not set, a netmask, the machine itself, already a documentation address
  return $address if $address =~ /\A(?:0\.0\.0\.0|255\.|127\.|192\.0\.2\.)/;
  return $self->placeholder( ipv4 => $address );
}

sub _ipv6 {
  my ( $self, $address ) = @_;
  return $address unless $address =~ /:.*:/ && defined inet_pton( AF_INET6, $address );
  return $address if $address =~ /\A(?:::1?|2001:db8:.*)\z/i;
  return $self->placeholder( ipv6 => lc $address );
}

sub sanitize {
  my ( $self, $docs ) = @_;
  $self->_walk( $docs, '', sub {
    my ( $value, $key ) = @_;
    my $kind = $BY_KEY{$key};
    return $value unless $kind && length $value;
    $self->placeholder( $kind, $value );
    # the domain of a full name is in other strings without the name in front
    $self->placeholder( domain => $1 ) if $kind eq 'fqdn' && $value =~ /\A[^.]+\.(.+\..+)\z/;
    return $value;
  } );
  # longest first, so that a value inside another does not break it up
  my @known = sort { length $b <=> length $a || $a cmp $b } grep { length >= 4 } keys %{ $self->{map} };
  my $known = @known ? join '|', map { quotemeta } @known : undef;
  return $self->_walk( $docs, '', sub {
    my ( $value, $key ) = @_;
    return $value if _structural($key);
    return $self->{map}{$value} if exists $self->{map}{$value};
    $value =~ s/($known)/$self->{map}{$1}/g if defined $known;
    return $self->_addresses( $value, $key );
  } );
}

# the values out of @values that are still in the documents
sub leaks {
  my ( $class, $docs, @values ) = @_;
  my %found;
  $class->_walk( $docs, '', sub {
    my ( $value ) = @_;
    $found{$_} = 1 for grep { defined && length && index( $value, $_ ) >= 0 } @values;
    return $value;
  } );
  return sort keys %found;
}

1;
