#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

# Every reading method against every controller there is a recording of in
# t/fixtures/, and against the invented one. A method either returns exactly
# the documented keys or says that this controller does not have it. Anything
# else, another error or a warning, is a defect.

use Scalar::Util qw( blessed );
use FakeiDRAC;
use iDRACShapes;
use WWW::iDRAC;

my %controller = ( 'the invented controller' => sub { FakeiDRAC->new } );
for my $file ( sort glob 't/fixtures/*/redfish.json' ) {
  my ( $name ) = $file =~ m{t/fixtures/([^/]+)/};
  $controller{$name} = sub { FakeiDRAC->from_file($file) };
}

for my $name ( sort keys %controller ) {
  subtest $name => sub {
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    my $fake  = $controller{$name}->();
    my $idrac = WWW::iDRAC->new( host => $fake->host, username => 'root', password => 'calvin', ua => $fake );

    my $facts = eval { $idrac->capabilities->facts };
    is( ref $facts, 'HASH', 'the facts are readable' ) or diag $@;
    note sprintf 'iDRAC %s, firmware %s, %s, Redfish %s', map { $_ // '?' } @{ $facts || {} }{qw( generation firmware model redfish_version )};

    for my $method ( read_methods() ) {
      my ( $area, $call ) = split /\./, $method;
      my $got;
      if ( eval { $got = $idrac->$area->$call; 1 } ) {
        shape_ok( $got, $method );
        ok( $idrac->capabilities->supports($method), $method.': supports agrees' );
      }
      else {
        my $error = $@;
        ok( blessed $error && $error->isa('WWW::iDRAC::Error::Unsupported'), $method.': not on this controller' ) or diag $error;
        note $error;
        ok( !$idrac->capabilities->supports($method), $method.': supports agrees' );
      }
    }

    like( $idrac->power->state // 'undef', qr/\A[a-z_]+\z/, 'power.state' );
    ok( defined eval { $idrac->capabilities->supports($_) }, $_.': supports answers' ) or diag $@
      for qw( power.on power.off power.restart power.cycle logs.clear_sel manager.restart );
    is( scalar $fake->seen(qr/\A(?:POST(?! \S*Sessions\z)|PATCH|PUT)/), 0, 'reading changes nothing on the controller' );
    is_deeply( \@warnings, [], 'no warnings' );
  };
}

done_testing;
