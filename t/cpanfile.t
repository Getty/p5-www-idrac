#!/usr/bin/env perl

use strict;
use warnings;
use File::Spec;
use FindBin;
use Test::More;

# The cpanfile is what the installer reads. A module the code loads but the
# cpanfile does not name is not missing at build time, it is missing when the
# library is loaded on a machine where the module is not installed yet.
#
# The list below is the runtime chain of lib/: what the code loads, named by
# the distribution that ships it. HTTP::Request comes with HTTP::Message,
# Net::OpenSSH::Constants comes with Net::OpenSSH. Type::Tiny is loaded by
# Types::Standard and stays named, so a missing Types::Standard does not take
# the types down with it.

my $cpanfile = File::Spec->catfile( $FindBin::Bin, File::Spec->updir, 'cpanfile' );

plan skip_all => 'cpanfile is not part of the distribution' unless -f $cpanfile;

open my $fh, '<', $cpanfile or die "cannot read $cpanfile: $!";
my %runtime;
my %test;
my $in_test = 0;
while ( my $line = <$fh> ) {
    if ( $line =~ /^\s*on\s+test\s*=>\s*sub\s*\{/ ) {
        $in_test = 1;
        next;
    }
    if ( $in_test && $line =~ /^\s*\};/ ) {
        $in_test = 0;
        next;
    }
    next unless $line =~ /^\s*requires\s+'([^']+)'/;
    if   ($in_test) { $test{$1}   = 1 }
    else           { $runtime{$1} = 1 }
}
close $fh;

my @runtime = qw(
    File::Temp
    HTTP::Message
    JSON::MaybeXS
    LWP::Protocol::https
    LWP::UserAgent
    Moo
    namespace::autoclean
    Net::OpenSSH
    Type::Tiny
    Types::Standard
);

my @test = qw(
    Test::More
    URI
);

for my $module ( @runtime ) {
    ok( $runtime{$module}, "$module is a declared prerequisite" );
}

for my $module ( @test ) {
    ok( $test{$module}, "$module is a declared test prerequisite" );
}

done_testing;
