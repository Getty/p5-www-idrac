#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use HTTP::Response;
use LWP::UserAgent;
use MIME::Base64 qw( decode_base64 );

{
  package T::Client;
  use Moo;
  has ua => ( is => 'ro', default => sub { LWP::UserAgent->new( timeout => 2 ) } );
  with 'WWW::iDRAC::Role::HTTP';
}

my $client = T::Client->new;

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

sub answer {
  my ( $status, $body, @header ) = @_;
  return HTTP::Response->new( $status, 'Status', [ 'Content-Type' => 'application/json', @header ], $body );
}

subtest 'build_request' => sub {
  my $get = $client->build_request( GET => 'https://idrac.test/redfish/v1/', token => 'abc' );
  is( $get->method, 'GET', 'method' );
  is( $get->header('Accept'), 'application/json', 'asks for JSON' );
  is( $get->header('X-Auth-Token'), 'abc', 'the session token' );
  is( $get->header('Authorization'), undef, 'and no Basic credentials with it' );
  is( $get->content, '', 'no body' );

  my $post = $client->build_request( POST => 'https://idrac.test/x', json => { ResetType => 'On' } );
  is( $post->header('Content-Type'), 'application/json', 'a JSON body is announced' );
  is( $post->content, '{"ResetType":"On"}', 'and encoded' );

  my $basic = $client->build_request( GET => 'https://idrac.test/x', basic => [ 'root', "p\x{e4}ss:word" ] );
  my ( $encoded ) = $basic->header('Authorization') =~ /\ABasic (\S+)\z/;
  is( decode_base64($encoded), "root:p\xc3\xa4ss:word", 'Basic credentials, a non-ASCII password as UTF-8' );
  is( $basic->header('X-Auth-Token'), undef, 'no token header without a token' );
};

subtest 'read_response on success' => sub {
  my $result = $client->read_response( answer( 201, '{"Id":"7"}', 'X-Auth-Token' => 'tok', Location => '/redfish/v1/Sessions/7' ), POST => 'https://idrac.test/s' );
  is_deeply( $result, { status => 201, data => { Id => '7' }, location => '/redfish/v1/Sessions/7', token => 'tok' }, 'status, data, location and token' );
  my $empty = $client->read_response( HTTP::Response->new( 204, 'No Content' ), POST => 'https://idrac.test/a' );
  is_deeply( $empty, { status => 204, data => undef, location => undef, token => undef }, 'an answer without a body' );
};

subtest 'the shapes an error comes in' => sub {
  my $extended = error_of {
    $client->read_response( answer( 400, '{"error":{"code":"Base.1.0.GeneralError","message":"A general error has occurred.","@Message.ExtendedInfo":[{"MessageId":"IDRAC.1.6.SYS403","Message":"Unable to complete the operation.","Resolution":"Retry later."}]}}' ), POST => 'https://idrac.test/a' );
  };
  isa_ok( $extended, 'WWW::iDRAC::Error::API' );
  is( $extended->http_status, 400, 'status as a number' );
  is( $extended->message_id, 'IDRAC.1.6.SYS403', 'the message id of the extended information' );
  is( $extended->api_message, 'Unable to complete the operation.', 'its message' );
  is( $extended->resolution, 'Retry later.', 'its resolution' );
  like( "$extended", qr{\APOST https://idrac\.test/a failed: 400 Status - Unable to complete the operation\.\z}, 'the message names the request' );

  my $plain = error_of { $client->read_response( answer( 404, '{"error":{"code":"Base.1.0.GeneralError","message":"Not here."}}' ), GET => 'https://idrac.test/b' ) };
  is( $plain->message_id, 'Base.1.0.GeneralError', 'without extended information the code' );
  is( $plain->api_message, 'Not here.', 'and the message' );
  is( $plain->resolution, undef, 'and no resolution' );
  ok( $plain->is_not_found, 'is_not_found' );

  my $bare = error_of { $client->read_response( answer( 400, '{"@Message.ExtendedInfo":[{"MessageId":"X.1","Message":"Top level."}]}' ), GET => 'https://idrac.test/c' ) };
  is( $bare->message_id, 'X.1', 'extended information without the error wrapper' );

  for my $body ( '<html>Unauthorized</html>', '', '[1,2]', '"text"' ) {
    my $odd = error_of { $client->read_response( HTTP::Response->new( 401, 'Unauthorized', [], $body ), GET => 'https://idrac.test/d' ) };
    isa_ok( $odd, 'WWW::iDRAC::Error::API', 'body '.( length $body ? $body : '(empty)' ) );
    ok( $odd->is_unauthorized && !defined $odd->api_message, 'status kept, nothing invented' );
  }
};

subtest 'no answer at all' => sub {
  my $error = error_of { $client->send_request( GET => 'http://127.0.0.1:9/redfish/v1/', basic => [ 'root', 'sekrit-pw' ] ) };
  isa_ok( $error, 'WWW::iDRAC::Error::Network' );
  like( "$error", qr{\AGET http://127\.0\.0\.1:9/redfish/v1/: 500}, 'names the request' );
  unlike( "$error", qr/sekrit-pw/, 'and not the password' );
};

done_testing;
