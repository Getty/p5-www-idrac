#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use JSON::MaybeXS;
use WWW::iDRAC::Util qw( text number health_of state_of list_of );

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

subtest 'text' => sub {
  is( text('PowerEdge T330'), 'PowerEdge T330', 'a string' );
  is( text("  PWR SPLY,495W \n"), 'PWR SPLY,495W', 'without padding' );
  is( text(0), '0', 'a zero is a value' );
  is( text($_), undef, 'nothing for '.( defined $_ ? ref $_ ? 'a reference' : "'$_'" : 'undef' ) ) for undef, '', '   ', [], {}, JSON::MaybeXS::true;
};

subtest 'number' => sub {
  is( number(23), 23, 'a number' );
  is( number('4800'), 4800, 'a number in a string' );
  is( number(-7), -7, 'a negative one' );
  is( number(0), 0, 'zero' );
  is( number($_), undef, 'nothing for '.( defined $_ ? ref $_ ? 'a reference' : "'$_'" : 'undef' ) ) for undef, '', 'N/A', [], JSON::MaybeXS::false;
  is( number('NaN'), undef, 'NaN is not a useful number' );
  is( number('nan'), undef, 'NaN, lower case' );
  is( number('Inf'), undef, 'Inf is not a useful number' );
  is( number('-Inf'), undef, '-Inf' );
  is( number('Infinity'), undef, 'Infinity' );
};

subtest 'health_of' => sub {
  is( health_of( { Health => 'OK' } ), 'ok', 'OK' );
  is( health_of( { Health => 'Warning' } ), 'warning', 'Warning' );
  is( health_of( { Health => 'Critical' } ), 'critical', 'Critical' );
  is( health_of($_), undef, 'nothing invented' ) for undef, {}, { Health => undef }, { Health => 'Unknown' }, 'OK', [];
};

subtest 'state_of' => sub {
  is( state_of('On'), 'on', 'On' );
  is( state_of('Off'), 'off', 'Off' );
  is( state_of('PoweringOn'), 'powering_on', 'two words' );
  is( state_of(undef), undef, 'undef' );
};

subtest 'list_of' => sub {
  is_deeply( [ list_of( [ { a => 1 }, undef, 'x', { b => 2 } ] ) ], [ { a => 1 }, { b => 2 } ], 'only the hashes' );
  is_deeply( [ list_of($_) ], [], 'nothing where there is no list' ) for undef, {}, 'x';
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
