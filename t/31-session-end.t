#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw( tempfile );

# The shape most scripts have: a client in a file-scoped variable that a
# named sub uses. Such a variable lives until global destruction, where
# objects go in no particular order, so the session has to be ended before
# that. PERL_HASH_SEED makes the order of destruction repeatable.

my ( $fh, $script ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
print {$fh} <<'SCRIPT';
use strict;
use warnings;
use FakeiDRAC;
use WWW::iDRAC;
{
  package Loud;
  our @ISA = ('FakeiDRAC');
  sub request { my ( $self, $request ) = @_; print 'sent ', $request->method, "\n" if $request->method eq 'DELETE'; $self->SUPER::request($request) }
}
my $fake  = Loud->new;
my $idrac = WWW::iDRAC->new( host => $fake->host, username => 'root', password => 'calvin', ua => $fake );
sub model { $idrac->system->info->{model} }
print 'model ', model(), "\n";
exit 3 if @ARGV;
SCRIPT
close $fh;

for my $seed ( 1 .. 3 ) {
  for my $how ( '', 'exit' ) {
    local $ENV{PERL_HASH_SEED} = $seed;
    my $out  = qx{"$^X" -Ilib -It/lib "$script" $how 2>&1};
    my $name = 'seed '.$seed.( $how ? ', leaving with exit' : ', running off the end' );
    like( $out, qr/^model PowerEdge T330$/m, $name.': the script ran' );
    like( $out, qr/^sent DELETE$/m, $name.': the session was ended' ) or diag $out;
    is( $? >> 8, $how ? 3 : 0, $name.': the exit code is the script\'s own' );
  }
}

done_testing;
