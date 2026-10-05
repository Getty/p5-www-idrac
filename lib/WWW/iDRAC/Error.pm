package WWW::iDRAC::Error;

# ABSTRACT: Exception base class for WWW::iDRAC

use Moo;

# No namespace::autoclean here: it would remove the overload stub.
use overload '""' => sub { $_[0]->message }, fallback => 1;

our $VERSION = '0.001';

=synopsis

    use Scalar::Util qw( blessed );

    my $ok = eval { $idrac->power->cycle; 1 };
    if ( !$ok && blessed $@ && $@->isa('WWW::iDRAC::Error::Unsupported') ) { ... }

=description

Every error WWW::iDRAC raises is an object of one of four subclasses:
L<WWW::iDRAC::Error::Validation> for wrong arguments,
L<WWW::iDRAC::Error::Network> when no HTTP answer arrived,
L<WWW::iDRAC::Error::API> when the iDRAC answered with an error, and
L<WWW::iDRAC::Error::Unsupported> when this controller does not have what was
asked for. All of them stringify to their message, so plain C<$@> matching
keeps working.

=cut

has message => (
  is       => 'ro',
  required => 1
);

=attr message

The human-readable description. The object stringifies to it.

=cut

sub throw {
  my ( $class, %arg ) = @_;
  die $class->new(%arg);
}

=method throw

    WWW::iDRAC::Error::Validation->throw( message => 'host is required' );

Builds the exception and dies with it.

=cut

1;
