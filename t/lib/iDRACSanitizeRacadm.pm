package iDRACSanitizeRacadm;

# The counterpart of iDRACSanitize for what racadm printed: text, not
# documents. It takes what identifies a machine, a network or a person out
# of the recorded texts before they are written to t/fixtures/, and a person
# reads the result before it is committed.
#
#   my $sanitizer = iDRACSanitizeRacadm->new->hide( host => 'idrac.lan' )->hide( user => 'root' );
#   my $clean     = $sanitizer->sanitize( { 'racadm license view' => $text } );   # map of command to text
#   my @leaks     = $sanitizer->leaks($clean);
#
# Two passes over all texts, so one value is one placeholder everywhere:
# the values of the lines whose name says they identify something are
# collected, then every text is rewritten. IPv4, IPv6 and MAC addresses, UUIDs and
# job ids are replaced by pattern, wherever they stand. Version lines keep
# their dotted numbers. This is a net, not a proof.

use strict;
use warnings;
use Socket qw( AF_INET6 inet_pton );

# the name of a line (case-insensitive, without a leading #) and what its value is
my @KEY_RULES = (
  [ qr/\A(?:unique identifier|license bound|systemservicetag|service tag|servicetag|sku)\z/ => 'tag' ],
  [ qr/\A(?:entitlement id|serial ?number|chassis service tag)\z/                          => 'serial' ],
  [ qr/\Aexpress svc code\z/                                                                => 'code' ],
  [ qr/\A(?:host name|hostname|dns rac name|domain name|current dns domain)\z/             => 'host' ],
  [ qr/\A(?:username|user name)\z/                                                          => 'user' ],
  [ qr/\A(?:password|sharename)\z/                                                          => 'secret' ],
  [ qr/\A(?:asset ?tag)\z/                                                                  => 'asset' ]
);

# a run of hex digits and colons that may be an IPv6 address; _is_ipv6 decides
my $IPV6 = qr/(?<![0-9A-Za-z:.])([0-9A-Fa-f:]{2,39})(?![0-9A-Za-z:])/;

sub _is_ipv6 { $_[0] =~ /:.*:/ && defined inet_pton( AF_INET6, $_[0] ) }

# what is no address of a machine: unspecified, loopback, documentation
sub _documented_ipv6 { $_[0] =~ /\A(?:::1?|2001:db8:.*)\z/i }

my %FORMAT = (
  tag    => sub { sprintf 'TAG%04d', $_[0] },
  serial => sub { sprintf 'SERIAL%04d', $_[0] },
  code   => sub { sprintf '%011d', $_[0] },
  host   => sub { sprintf 'host-%d', $_[0] },
  user   => sub { sprintf 'user-%d', $_[0] },
  secret => sub { sprintf 'REDACTED-%d', $_[0] },
  asset  => sub { sprintf 'ASSET%04d', $_[0] },
  mac    => sub { sprintf '00:00:5E:00:53:%02X', $_[0] % 256 },
  ipv4   => sub { sprintf '192.0.2.%d', $_[0] % 256 },
  ipv6   => sub { sprintf '2001:db8::%x', $_[0] },
  uuid   => sub { sprintf '00000000-0000-0000-0000-%012d', $_[0] },
  job    => sub { sprintf '%012d', $_[0] }
);

sub new { bless { map => {}, count => {}, named => {} }, $_[0] }

sub _placeholder {
  my ( $self, $kind, $value ) = @_;
  return $self->{map}{ lc $value } //= $FORMAT{$kind}->( ++$self->{count}{$kind} );
}

sub hide {
  my ( $self, $kind, $value ) = @_;
  return $self unless defined $value && length $value;
  $self->{named}{ lc $value } = $self->_placeholder( $kind, $value );
  return $self;
}

sub _filler { $_[0] =~ /\A(?:|n\/?a|none|null|unknown|not (?:specified|available|applicable|installed|set)|0+|-+|enabled|disabled)\z/i }

sub collect {
  my ( $self, $text ) = @_;
  for my $line ( split /\n/, $text ) {
    # Name = value, and the Name value of "remoteimage -s" (UserName x,
    # ShareName //host/share/a.iso), where the name is one word
    my ( $key, $value ) = $line =~ /\A\s*#?([A-Za-z][A-Za-z #]*?)\s*=\s*(.*?)\s*\z/;
    ( $key, $value ) = $line =~ /\A\s*([A-Za-z]+)[ \t]+(\S.*?)\s*\z/ unless defined $key;
    next unless defined $key;
    $value =~ s/\A\[\s*|\s*\]\z//g;
    next if _filler($value);
    my ($rule) = grep { lc($key) =~ $_->[0] } @KEY_RULES or next;
    $self->hide( $rule->[1], $value );
    # the host of a share is hidden wherever it stands, not only in the share
    my ($host) = $value =~ m{\A(?://|[a-z]+://)(?:[^/\@]*\@)?([^/:\s]+)}i;
    ($host) = $value =~ m{\A([A-Za-z0-9.-]+):/} unless defined $host;
    $self->hide( host => $host ) if defined $host && lc($key) eq 'sharename';
  }
  return $self;
}

sub rewrite {
  my ( $self, $text ) = @_;
  # longest first, so a name is replaced before the part of it that is one too
  for my $known ( sort { length $b <=> length $a } keys %{ $self->{named} } ) {
    $text =~ s/(?<![A-Za-z0-9])\Q$known\E(?![A-Za-z0-9])/$self->{named}{$known}/gi;
  }
  my @out;
  for my $line ( split /\n/, $text, -1 ) {
    my $keep_numbers = $line =~ /version|firmware|build/i;
    $line =~ s{\b((?:[0-9A-Fa-f]{2}[:-]){5,7}[0-9A-Fa-f]{2})\b}{ $1 =~ /\A00:00:5E:00:53:/i ? $1 : $self->_placeholder( mac => uc $1 ) }ge;
    $line =~ s{$IPV6}{ $self->_ipv6($1) }ge;
    $line =~ s{\b([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\b}{ $1 =~ /\A00000000-0000-0000-0000-/ ? $1 : $self->_placeholder( uuid => $1 ) }gie;
    unless ($keep_numbers) {
      $line =~ s{(?<![0-9.])((?:[0-9]{1,3}\.){3}[0-9]{1,3})(?![0-9]|\.[0-9])}{ $self->_ipv4($1) }ge;
    }
    $line =~ s{\b(JID|RID)_([0-9]+)\b}{ $1.'_'.$self->_placeholder( job => $2 ) }ge;
    push @out, $line;
  }
  return join "\n", @out;
}

sub _ipv6 {
  my ( $self, $address ) = @_;
  return $address unless _is_ipv6($address);
  return $address if _documented_ipv6($address);
  return $self->_placeholder( ipv6 => lc $address );
}

sub _ipv4 {
  my ( $self, $address ) = @_;
  return $address if grep { $_ > 255 } split /\./, $address;
  return $address if $address =~ /\A(?:0\.0\.0\.0|255\.|127\.|192\.0\.2\.)/;
  return $self->_placeholder( ipv4 => $address );
}

# a map of command to text; the commands are rewritten too, they hold a job id
sub sanitize {
  my ( $self, $recording ) = @_;
  $self->collect($_) for values %$recording;
  return { map { $self->rewrite($_) => $self->rewrite( $recording->{$_} ) } keys %$recording };
}

# what still looks like what should be gone: kinds and places, never values
sub leaks {
  my ( $self, $clean ) = @_;
  my @leak;
  for my $command ( sort keys %$clean ) {
    my $text = $clean->{$command};
    for my $known ( sort keys %{ $self->{named} } ) {
      next if $self->{named}{$known} eq $known;
      push @leak, 'a hidden value in "'.$command.'"' if $text =~ /(?<![A-Za-z0-9])\Q$known\E(?![A-Za-z0-9])/i || $command =~ /\Q$known\E/i;
    }
    push @leak, 'an IPv4 address in "'.$command.'"'
      if grep { !/\A(?:0\.0\.0\.0|255\.|127\.|192\.0\.2\.)/ } grep { !/version|firmware|build/i } map { /((?:[0-9]{1,3}\.){3}[0-9]{1,3})/g } grep { !/version|firmware|build/i } split /\n/, $text;
    push @leak, 'an IPv6 address in "'.$command.'"' if grep { _is_ipv6($_) && !_documented_ipv6($_) } $text =~ /$IPV6/g;
    push @leak, 'a MAC address in "'.$command.'"' if grep { !/\A00:00:5E:00:53:/i } $text =~ /\b((?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})\b/g;
  }
  return @leak;
}

1;
