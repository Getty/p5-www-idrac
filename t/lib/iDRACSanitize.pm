package iDRACSanitize;

# Takes what identifies a machine, a network or a person out of recorded
# Redfish documents, before they are written to t/fixtures/. The repository
# is public; a recording that was not through here is not committed, and a
# person reads it before it is.
#
#   my $sanitizer = iDRACSanitize->new->hide( host => 'idrac.lan' )->hide( secret => $password );
#   my $clean     = $sanitizer->sanitize( \%docs );     # a map of path to document
#   my @leaks     = $sanitizer->leaks($clean);          # "a tag in /redfish/v1/..." - kinds, never values
#
# What it does, in this order:
#
#   1. Collect: the value of every key in @KEY_RULES gets a placeholder, the
#      same value the same one everywhere, whatever its case. Keys are
#      matched on their last dotted component, because Dell's attribute
#      documents name theirs "Users.3.UserName".
#   2. Rewrite every string: a collected value becomes its placeholder, also
#      inside other strings; names under a collected domain, e-mail
#      addresses, UUIDs, MAC and IP addresses become placeholders from the
#      documentation ranges.
#   3. Leave out what nobody has looked at or what is free text about people:
#      the keys in %DROP, and the text of log messages.
#
# Numbers and booleans are not touched, so a recording still shows what type
# the controller sends. Structural strings, that is @odata values and action
# targets, keep their path; a full URL loses its host.
#
# This is a net, not a proof. The recorder keeps only the kinds of document
# the tests read, which is what keeps most of a controller out of here.

use strict;
use warnings;
use B ();
use Socket qw( AF_INET6 inet_pton );

# what a key says about its value: a pattern on the last dotted component of
# the key, in lower case, and the kind of placeholder the value gets
my @KEY_RULES = (
  [ qr/\A(?:serialnumber|durablename|entitlementid)\z/                                                => 'serial' ],
  [ qr/\A(?:sku|servicetag|chassisservicetag|nodeid)\z/                                               => 'tag' ],
  [ qr/\Aexpressservicecode\z/                                                                        => 'code' ],
  [ qr/\Aassettag\z/                                                                                  => 'asset' ],
  [ qr/uuid\z/                                                                                        => 'uuid' ],
  [ qr/\Afqdn\z/                                                                                      => 'fqdn' ],
  [ qr/\A(?:hostname|dnsracname)\z/                                                                   => 'host' ],
  [ qr/domainname\z/                                                                                  => 'domain' ],
  [ qr/\Ausername\z|dn\z/                                                                             => 'user' ],
  [ qr/(?:password|passphrase|secret|community|token|key)\z/                                          => 'secret' ],
  [ qr/datacenter|rack|aisle|room|site|building|city|street|postal|country|contact|owner|organi[sz]ation|\Acsr|\Aimage(?:name)?\z/ => 'place' ]
);

# keys that are left out with everything below them
my %DROP = map { $_ => 1 } qw( Oem Location PostalAddress MessageArgs );

# what controllers write where they have nothing to say
my $FILLER = qr/\A(?:n\/?a|none|null|unknown|default|not (?:specified|available|applicable|installed|set)|0+|-+|\s*)\z/i;

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
  email  => sub { sprintf 'user-%d@example.org', $_[0] },
  secret => sub { sprintf 'REDACTED-%d', $_[0] },
  place  => sub { sprintf 'REMOVED-%d', $_[0] },
  mac    => sub { sprintf '00:00:5E:00:53:%02X', $_[0] % 256 },
  ipv4   => sub { sprintf '192.0.2.%d', $_[0] % 256 },
  ipv6   => sub { sprintf '2001:db8::%x', $_[0] }
);

sub new { bless { map => {}, kind => {}, count => {}, named => {} }, $_[0] }

# the placeholder of a value, the same one each time and whatever its case
sub placeholder {
  my ( $self, $kind, $value ) = @_;
  my $known = lc $value;
  $self->{kind}{$known} //= $kind;
  return $self->{map}{$known} //= $FORMAT{$kind}->( ++$self->{count}{$kind} );
}

# The same for a value that is known to identify something: one that a key
# named, or one that was hidden by hand. Only these are searched for inside
# other strings and by leaks(). An address that merely has the form of one,
# like a firmware version, gets a placeholder where it stands and no more.
sub name {
  my ( $self, $kind, $value ) = @_;
  $self->{named}{ lc $value } = 1;
  return $self->placeholder( $kind, $value );
}

# a value known from outside the documents: the address the recording was
# made at, the user it was made as, the password
sub hide {
  my ( $self, $kind, $value ) = @_;
  return $self unless defined $value && length $value;
  $kind = 'ipv4' if $kind eq 'host' && $value =~ /\A[0-9.]+\z/;
  $kind = 'ipv6' if $kind eq 'host' && $value =~ /:/;
  $self->name( $kind, $value );
  return $self;
}

# a JSON string, as opposed to a number
sub _is_string { !ref $_[0] && defined $_[0] && ( B::svref_2object( \$_[0] )->FLAGS & B::SVp_POK ) ? 1 : 0 }

sub _kind_of {
  my ( $key ) = @_;
  my ( $last ) = lc($key) =~ /([^.]*)\z/;
  for my $rule (@KEY_RULES) { return $rule->[1] if $last =~ $rule->[0] }
  return;
}

sub _structural { $_[0] =~ /\@odata\.|\Atarget\z/ }

sub _collect {
  my ( $self, $node, $key ) = @_;
  if ( ref $node eq 'HASH' ) { $self->_collect( $node->{$_}, $_ ) for grep { !$DROP{$_} } sort keys %$node; return }
  if ( ref $node eq 'ARRAY' ) { $self->_collect( $_, $key ) for @$node; return }
  return unless _is_string($node) && $node !~ $FILLER;
  my $kind = _kind_of($key) or return;
  $self->name( $kind, $node );
  # the domain of a full name is in other strings without the name in front,
  # and so are the domains above it
  my $domain = $kind eq 'fqdn' ? ( $node =~ /\A[^.]+\.(.+\..+)\z/ )[0] : $kind eq 'domain' ? $node : undef;
  while ( defined $domain && $domain =~ /\./ ) {
    $self->name( domain => $domain );
    ( $domain ) = $domain =~ /\A[^.]+\.(.+\..+)\z/;
  }
  return;
}

sub _rewrite {
  my ( $self, $node, $key ) = @_;
  if ( ref $node eq 'HASH' ) {
    my %out = map { $_ => $self->_rewrite( $node->{$_}, $_ ) } grep { !$DROP{$_} } sort keys %$node;
    # the text of a log entry names users and where they came from
    $out{Message} = 'Message text removed'.( _is_string( $node->{MessageId} ) ? ' ('.$node->{MessageId}.')' : '' ).'.'
      if _is_string( $node->{Message} ) && ( exists $node->{MessageId} || exists $node->{Created} );
    return \%out;
  }
  return [ map { $self->_rewrite( $_, $key ) } @$node ] if ref $node eq 'ARRAY';
  return $node unless _is_string($node);
  return $self->_rewrite_string( "$node", $key );
}

sub _rewrite_string {
  my ( $self, $text, $key ) = @_;
  # an address of a document or an action: only the host of a full URL goes
  if ( _structural($key) ) { $text =~ s{\A([a-z][a-z0-9+.-]*://)[^/]+}{${1}idrac.test}i; return $text }
  my $map = $self->{map};
  return $map->{ lc $text } if $self->{named}{ lc $text };
  if ( my $domains = $self->{domains} ) { $text =~ s{((?:[A-Za-z0-9-]+\.)+(?:$domains))(?![A-Za-z0-9-])}{ $self->placeholder( fqdn => $1 ) }gie }
  if ( my $known   = $self->{known} )   { $text =~ s{($known)}{ $map->{ lc $1 } }gie }
  $text =~ s{([A-Za-z0-9._%+-]+\@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)}{ $self->placeholder( email => $1 ) }ge;
  $text =~ s{\b([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\b}{ $self->_unless_placeholder( uuid => $1, qr/\A0{8}-/ ) }gie;
  # six groups are a MAC address, eight a WWN
  $text =~ s{\b((?:[0-9A-Fa-f]{2}[:-]){5,7}[0-9A-Fa-f]{2})\b}{ $self->_unless_placeholder( mac => uc $1, qr/\A00:00:5E:00:53:/ ) }ge;
  $text = $self->placeholder( mac => uc join ':', $text =~ /(..)/g ) if $key =~ /mac/i && $text =~ /\A[0-9A-Fa-f]{12}\z/;
  # a firmware version has the form of an IPv4 address
  $text =~ s{(?<![0-9.])((?:[0-9]{1,3}\.){3}[0-9]{1,3})(?![0-9]|\.[0-9])}{ $self->_ipv4($1) }ge unless $key =~ /version|firmware/i;
  $text =~ s{(?<![0-9A-Za-z:])([0-9A-Fa-f:]{2,39})(?![0-9A-Za-z:])}{ $self->_ipv6($1) }ge;
  return $text;
}

# a value that is one of ours already stays; a match inside the replacement
# of a substitution would lose $1, hence a sub
sub _unless_placeholder {
  my ( $self, $kind, $value, $ours ) = @_;
  return $value =~ $ours ? $value : $self->placeholder( $kind, $value );
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
  $self->_collect( $docs, '' );
  my $map = $self->{map};
  # longest first, so that a value inside another does not break it up
  my $alternatives = sub { join( '|', map { quotemeta } sort { length $b <=> length $a || $a cmp $b } @_ ) || undef };
  my @named = keys %{ $self->{named} };
  $self->{known}   = $alternatives->( grep { length >= 4 } @named );
  $self->{domains} = $alternatives->( grep { $self->{kind}{$_} eq 'domain' } @named );
  return { map { $_ => $self->_rewrite( $docs->{$_}, '' ) } sort keys %$docs };
}

# Where a named value is still to be found, as "a <kind> in <path>". The
# report names kinds, never the values: it is printed.
sub leaks {
  my ( $self, $docs ) = @_;
  my $map = $self->{map};
  # a value that is itself one of the placeholders cannot be told from them
  my %ours    = map { lc $_ => 1 } values %$map;
  my @needles = grep { !$ours{$_} } keys %{ $self->{named} };
  my ( %found, $path );
  my $look = sub {
    my ( $text ) = @_;
    for my $needle (@needles) {
      next unless length $needle >= 4 ? $text =~ /(?<![A-Za-z0-9])\Q$needle\E(?![A-Za-z0-9])/i : lc $text eq $needle;
      my $kind = $self->{kind}{$needle};
      $found{ ( $kind =~ /\A[aeiou]/ ? 'an ' : 'a ' ).$kind.' in '.$path } = 1;
    }
  };
  my $walk;
  $walk = sub {
    my ( $node ) = @_;
    if ( ref $node eq 'HASH' ) { for ( sort keys %$node ) { $look->($_); $walk->( $node->{$_} ) } }
    elsif ( ref $node eq 'ARRAY' ) { $walk->($_) for @$node }
    elsif ( _is_string($node) ) { $look->("$node") }
  };
  for ( sort keys %$docs ) { $path = $_; $look->($path); $walk->( $docs->{$path} ) }
  return sort keys %found;
}

1;
