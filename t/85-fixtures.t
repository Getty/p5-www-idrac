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
#   { "unsupported": [ "system.memory", "power.cycle" ],   methods that throw Unsupported, the switching ones included
#     "empty":       [ "logs.sel" ],                   methods that return an empty list
#     "undef":       { "system.info": [ "asset_tag" ] } }   keys that are undef in every row
#
# The same file covers what is served over racadm (bios, jobs, virtual_media),
# against the racadm.json beside the Redfish recording. "license" names the
# license the controller has:
#
#   { "license": "express" }
#
# Everything else has to be there. A recording without the file fails, and
# the test prints what it found, to be read, corrected where the code is
# wrong, and saved.

use JSON::MaybeXS;
use Scalar::Util qw( blessed );
use FakeiDRAC;
use FakeRacadm;
use iDRACShapes;
use WWW::iDRAC;

my $JSON = JSON::MaybeXS->new( utf8 => 1, canonical => 1, pretty => 1 );

my %controller = (
  'the invented controller' => {
    fake   => sub { FakeiDRAC->new },
    racadm => sub { FakeRacadm->new },
    expect => { license => 'enterprise', unsupported => [ 'power.cycle', 'system.memory' ], empty => [ 'jobs.list' ], undef => { 'system.info' => ['asset_tag'], 'virtual_media.status' => [ 'username', 'share' ] } }
  }
);
for my $file ( sort glob 't/fixtures/*/redfish.json' ) {
  my ( $dir, $name ) = $file =~ m{\A(t/fixtures/([^/]+))/};
  my $expect;
  if ( open my $fh, '<:raw', $dir.'/expect.json' ) { $expect = $JSON->decode( do { local $/; <$fh> } ) }
  my $racadm = -e $dir.'/racadm.json' ? sub { FakeRacadm->from_file( $dir.'/racadm.json' ) } : undef;
  $controller{$name} = { fake => sub { FakeiDRAC->from_file($file) }, racadm => $racadm, expect => $expect, expect_file => $dir.'/expect.json' };
}

for my $name ( sort keys %controller ) {
  subtest $name => sub {
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    my $fake  = $controller{$name}{fake}->();
    my %found = ( unsupported => [], empty => [], undef => {} );
    my $racadm = $controller{$name}{racadm} ? $controller{$name}{racadm}->() : undef;
    my $idrac  = WWW::iDRAC->new(
      host => $fake->host, username => 'root', password => 'calvin', ua => $fake,
      ( $racadm ? ( racadm => $racadm->transport ) : ( ssh => 0 ) )
    );

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

    if ($racadm) {
      for my $call ( racadm_methods() ) {
        my ( $method, @arg ) = @$call;
        my ( $area, $name ) = split /\./, $method;
        my $got;
        if ( eval { $got = $idrac->$area->$name(@arg); 1 } ) {
          if ( $method eq 'bios.groups' ) {
            ok( !grep( { ref $_ || !length } @$got ), $method.': a list of names' );
          }
          elsif ( $method eq 'bios.get' ) {
            ok( !ref $got, $method.': a plain value' );
          }
          else { shape_ok( $got, $method ) }
          ok( $idrac->capabilities->supports($method), $method.': supports agrees' );
          my @rows = grep { ref $_ eq 'HASH' } ref $got eq 'ARRAY' ? @$got : $got;
          push @{ $found{empty} }, $method if ref $got eq 'ARRAY' && !@$got;
          my @undef = @rows ? grep { my $key = $_; !grep { defined $_->{$key} } @rows } sort keys %{ $rows[0] } : ();
          $found{undef}{$method} = \@undef if @undef;
          if ( $method eq 'jobs.list' && @$got && $name eq 'list' ) {
            my $job = eval { $idrac->jobs->get( $got->[0]{id} ) };
            shape_ok( $job, 'jobs.get' );
            is_deeply( $job, $got->[0], 'jobs.get: the same job as the list shows' );
            my $gone = eval { $idrac->jobs->get('JID_000000000001'); 1 } ? undef : $@;
            ok( ref $gone && $gone->isa('WWW::iDRAC::Error::API') && $gone->is_not_found, 'jobs.get: a job it does not have is a not found' );
          }
        }
        else {
          my $error = $@;
          ok( blessed $error && $error->isa('WWW::iDRAC::Error::Unsupported'), $method.': not on this controller' ) or diag $error;
          note $error;
          ok( !$idrac->capabilities->supports($method), $method.': supports agrees' );
          push @{ $found{unsupported} }, $method;
        }
      }
      $found{license} = $idrac->capabilities->license;
      # the writing methods are only asked about, never called
      for my $method (qw( bios.set bios.commit jobs.delete virtual_media.connect virtual_media.disconnect )) {
        my $offered = eval { $idrac->capabilities->supports($method) };
        ok( defined $offered, $method.': supports answers' ) or diag $@;
        push @{ $found{unsupported} }, $method if defined $offered && !$offered;
      }
      is_deeply( [ grep { !/\Aracadm (?:get|license view|jobqueue view|remoteimage -s)/ } @{ $racadm->commands } ], [], 'only reading commands were sent' );
      ok( $racadm->connected, 'the racadm connection is open while the client lives' );
    }
    # the switching methods are only asked about, never called
    for my $method (qw( power.on power.off power.restart power.cycle logs.clear_sel manager.restart )) {
      my $offered = eval { $idrac->capabilities->supports($method) };
      ok( defined $offered, $method.': supports answers' ) or diag $@;
      push @{ $found{unsupported} }, $method if defined $offered && !$offered;
    }
    undef $idrac;
    if ($racadm) { ok( !$racadm->connected, 'the racadm connection is closed when the client is gone' ) }
    @{ $found{unsupported} } = sort @{ $found{unsupported} };
    is( scalar $fake->seen(qr/\A(?:POST(?! \S*Sessions\z)|PATCH|PUT)/), 0, 'reading changes nothing on the controller' );
    is_deeply( \@warnings, [], 'no warnings' );

    if ( my $expect = $controller{$name}{expect} ) {
      my %expect = ( ( $racadm ? ( license => $expect->{license} ) : () ), unsupported => [ sort @{ $expect->{unsupported} || [] } ], empty => [ sort @{ $expect->{empty} || [] } ], undef => { map { $_ => [ sort @{ $expect->{undef}{$_} } ] } keys %{ $expect->{undef} || {} } } );
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
