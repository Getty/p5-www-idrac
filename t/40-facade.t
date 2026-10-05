#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use WWW::iDRAC;

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

my %login = ( username => 'root', password => 'calvin' );

subtest 'construction' => sub {
  my $idrac = WWW::iDRAC->new( host => 'idrac.example.org', %login );
  is( $idrac->base_url, 'https://idrac.example.org', 'https and the host' );
  is( WWW::iDRAC->new( host => '192.0.2.10:8443', %login )->base_url, 'https://192.0.2.10:8443', 'an address with a port' );
  is( WWW::iDRAC->new( host => '[2001:db8::10]', %login )->base_url, 'https://[2001:db8::10]', 'an IPv6 address' );
  for my $host ( 'https://idrac.example.org', 'idrac.example.org/redfish', 'two words', '' ) {
    isa_ok( error_of { WWW::iDRAC->new( host => $host, %login ) }, 'WWW::iDRAC::Error::Validation', "host '$host'" );
  }
  ok( error_of { WWW::iDRAC->new( host => 'idrac.example.org', username => 'root' ) }, 'the password is required' );
};

subtest 'the user agent' => sub {
  my $default = WWW::iDRAC->new( host => 'idrac.example.org', %login )->ua;
  isa_ok( $default, 'LWP::UserAgent' );
  is( $default->timeout, 60, 'waits 60 seconds' );
  like( $default->agent, qr{\AWWW-iDRAC/}, 'names itself' );
  is( $default->max_redirect, 0, 'follows no redirect, which would carry the token or the password to wherever it leads' );
  ok( $default->ssl_opts('verify_hostname'), 'verifies the certificate by default' );
  is( $default->ssl_opts('SSL_verify_mode'), undef, 'and does not touch the verify mode' );

  my $pinned = WWW::iDRAC->new( host => 'idrac.example.org', %login, ssl_fingerprint => 'sha256$ab12', timeout => 10 )->ua;
  is( $pinned->ssl_opts('SSL_fingerprint'), 'sha256$ab12', 'a pinned certificate' );
  ok( $pinned->ssl_opts('verify_hostname'), 'with verification still on' );
  is( $pinned->timeout, 10, 'timeout' );

  is( WWW::iDRAC->new( host => 'idrac.example.org', %login, ssl_ca_file => '/etc/ssl/idrac.pem' )->ua->ssl_opts('SSL_ca_file'), '/etc/ssl/idrac.pem', 'a CA file' );

  my $open = WWW::iDRAC->new( host => 'idrac.example.org', %login, verify_ssl => 0 )->ua;
  ok( !$open->ssl_opts('verify_hostname'), 'verify_ssl => 0 turns the name check off' );
  is( $open->ssl_opts('SSL_verify_mode'), 0, 'and the certificate check' );

  my $own = WWW::iDRAC->new( host => 'idrac.example.org', %login, ssl_opts => { SSL_version => 'TLSv1_2', verify_hostname => 0 } )->ua;
  is( $own->ssl_opts('SSL_version'), 'TLSv1_2', 'ssl_opts are passed on' );
  ok( !$own->ssl_opts('verify_hostname'), 'and win over the defaults' );
};

subtest 'the parts share one transport' => sub {
  my $fake  = FakeiDRAC->new;
  my $idrac = WWW::iDRAC->new( host => $fake->host, %login, ua => $fake );
  isa_ok( $idrac->redfish, 'WWW::iDRAC::Redfish' );
  is( $idrac->redfish->base_url, 'https://idrac.test', 'pointed at the host' );
  is( $idrac->system->redfish, $idrac->redfish, 'system uses the transport of the facade' );
  is( $idrac->system->info->{model}, 'PowerEdge T330', 'and reaches the controller' );
  is( $idrac->logout, 1, 'logout ends the session' );
  is( $fake->sessions, 0, 'on the controller' );

  my $basic = WWW::iDRAC->new( host => $fake->host, %login, ua => $fake, session => 0 );
  $basic->system->info;
  is( $fake->sessions, 0, 'session => 0 reaches the transport' );
};

subtest 'no session is left behind' => sub {
  my $fake = FakeiDRAC->new;
  {
    my $idrac = WWW::iDRAC->new( host => $fake->host, %login, ua => $fake );
    $idrac->system->info;
    is( $fake->sessions, 1, 'open inside the scope' );
  }
  is( $fake->sessions, 0, 'ended when the facade goes away' );

  my $system = WWW::iDRAC->new( host => $fake->host, %login, ua => $fake )->system;
  is( $system->info->{model}, 'PowerEdge T330', 'a part outlives the facade it came from' );
  is( $fake->sessions, 1, 'with its session' );
  undef $system;
  is( $fake->sessions, 0, 'which ends with the part' );
};

done_testing;
