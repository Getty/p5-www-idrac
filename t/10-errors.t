#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use WWW::iDRAC::Error;
use WWW::iDRAC::Error::API;
use WWW::iDRAC::Error::Network;
use WWW::iDRAC::Error::Unsupported;
use WWW::iDRAC::Error::Validation;

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

subtest 'classes and stringification' => sub {
  my $e = WWW::iDRAC::Error::API->new( message => 'boom', http_status => 404 );
  isa_ok( $e, 'WWW::iDRAC::Error' );
  is( "$e", 'boom', 'stringifies to the message' );
  ok( $e->is_not_found && !$e->is_unauthorized, 'predicates' );
  is( $e->message_id, undef, 'no message id unless given' );
  isa_ok( WWW::iDRAC::Error::Validation->new( message => 'x' ), 'WWW::iDRAC::Error' );
  isa_ok( WWW::iDRAC::Error::Network->new( message => 'x' ), 'WWW::iDRAC::Error' );
};

subtest 'throw' => sub {
  my $thrown = error_of { WWW::iDRAC::Error::Validation->throw( message => 'thrown' ) };
  isa_ok( $thrown, 'WWW::iDRAC::Error::Validation' );
  like( "$thrown", qr/\Athrown\z/, 'plain $@ matching keeps working' );
};

subtest 'unsupported' => sub {
  my $e = error_of { WWW::iDRAC::Error::Unsupported->throw( message => 'no', capability => 'power.cycle', reason => 'not offered' ) };
  isa_ok( $e, 'WWW::iDRAC::Error' );
  is( $e->capability, 'power.cycle', 'names the capability' );
  is( $e->reason, 'not offered', 'and the reason' );
  ok( !eval { WWW::iDRAC::Error::Unsupported->new( message => 'no' ); 1 }, 'the capability is required' );
};

done_testing;
