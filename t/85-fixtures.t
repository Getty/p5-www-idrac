#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

# Every reading method against every controller there is a recording of in
# t/fixtures/, and against the invented one. A method either returns exactly
# the documented keys or says that this controller does not have it. Anything
# else, another error or a warning, is a defect.
#
# The right keys are not enough: a method that looks for a field under the
# wrong name returns them all, undef. So each recording has an expect.json
# beside it that says what this controller does not have:
#
#   { "unsupported": [ "system.memory" ],              methods that throw Unsupported
#     "empty":       [ "logs.sel" ],                   methods that return an empty list
#     "undef":       { "system.info": [ "asset_tag" ] } }   keys that are undef in every row
#
# Everything else has to be there. A recording without the file fails, and
# the test prints what it found, to be read, corrected where the code is
# wrong, and saved.

use JSON::MaybeXS;
use Scalar::Util qw( blessed );
use FakeiDRAC;
use iDRACShapes;
use WWW::iDRAC;

my $JSON = JSON::MaybeXS->new( utf8 => 1, canonical => 1, pretty => 1 );

my %controller = (
  'the invented controller' => {
    fake   => sub { FakeiDRAC->new },
    expect => { unsupported => ['system.memory'], empty => [], undef => { 'system.info' => ['asset_tag'] } }
  }
);
for my $file ( sort glob 't/fixtures/*/redfish.json' ) {
  my ( $dir, $name ) = $file =~ m{\A(t/fixtures/([^/]+))/};
  my $expect;
  if ( open my $fh, '<:raw', $dir.'/expect.json' ) { $expect = $JSON->decode( do { local $/; <$fh> } ) }
  $controller{$name} = { fake => sub { FakeiDRAC->from_file($file) }, expect => $expect, expect_file => $dir.'/expect.json' };
}

for my $name ( sort keys %controller ) {
  subtest $name => sub {
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    my $fake  = $controller{$name}{fake}->();
    my %found = ( unsupported => [], empty => [], undef => {} );
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
        my @rows = grep { ref $_ eq 'HASH' } ref $got eq 'ARRAY' ? @$got : $got;
        push @{ $found{empty} }, $method unless @rows;
        my @undef = @rows ? grep { my $key = $_; !grep { defined $_->{$key} } @rows } sort keys %{ $rows[0] } : ();
        $found{undef}{$method} = \@undef if @undef;
      }
      else {
        my $error = $@;
        ok( blessed $error && $error->isa('WWW::iDRAC::Error::Unsupported'), $method.': not on this controller' ) or diag $error;
        note $error;
        ok( !$idrac->capabilities->supports($method), $method.': supports agrees' );
        push @{ $found{unsupported} }, $method;
      }
    }

    like( $idrac->power->state // 'undef', qr/\A[a-z_]+\z/, 'power.state' );
    ok( defined eval { $idrac->capabilities->supports($_) }, $_.': supports answers' ) or diag $@
      for qw( power.on power.off power.restart power.cycle logs.clear_sel manager.restart );
    is( scalar $fake->seen(qr/\A(?:POST(?! \S*Sessions\z)|PATCH|PUT)/), 0, 'reading changes nothing on the controller' );
    is_deeply( \@warnings, [], 'no warnings' );

    if ( my $expect = $controller{$name}{expect} ) {
      my %expect = ( unsupported => [ sort @{ $expect->{unsupported} || [] } ], empty => [ sort @{ $expect->{empty} || [] } ], undef => { map { $_ => [ sort @{ $expect->{undef}{$_} } ] } keys %{ $expect->{undef} || {} } } );
      is_deeply( \%found, \%expect, 'what this controller lacks is what was written down for it, no more and no less' )
        or diag "found:\n".$JSON->encode( \%found );
    }
    else {
      fail( 'there is no '.$controller{$name}{expect_file} );
      diag 'This is what the recording shows. Read it: a key in "undef" may be a field the code looks for under the wrong name.', "\n",
        'Save it as '.$controller{$name}{expect_file}.' once it is right:', "\n", $JSON->encode( \%found );
    }
  };
}

done_testing;
