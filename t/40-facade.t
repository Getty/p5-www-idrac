#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use FakeRacadm;
use WWW::iDRAC;

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

my %login = ( username => 'root', password => 'calvin' );

subtest 'construction' => sub {
  my $idrac = WWW::iDRAC->new( host => 'idrac.example.org', %login );
  is( $idrac->base_url, 'https://idrac.example.org', 'https and the host' );
  is( WWW::iDRAC->new( host => '192.0.2.10:8443', %login )->base_url, 'https://192.0.2.10:8443', 'an address with a port' );
  is( WWW::iDRAC->new( host => '[2001:db8::10]', %login )->base_url, 'https://[2001:db8::10]', 'an IPv6 address' );
  for my $host ( 'https://idrac.example.org', 'idrac.example.org/redfish', 'two words', '' ) {
    my $error = error_of { WWW::iDRAC->new( host => $host, username => 'root', password => 'calvin' ) };
    isa_ok( $error, 'WWW::iDRAC::Error::Validation', "host '$host'" );
    unlike( "$error", qr/\Q$host\E/, 'the message does not echo the rejected host' ) if length $host;
  }
  for my $bad ( [ username => undef ], [ username => '' ], [ password => undef ], [ password => '' ] ) {
    my ( $field, $value ) = @$bad;
    my $args = { host => 'idrac.example.org', username => 'root', password => 'calvin' };
    $args->{$field} = $value;
    isa_ok( error_of { WWW::iDRAC->new( $args->%* ) }, 'WWW::iDRAC::Error::Validation', "$field required when missing" );
  }
  isa_ok( error_of { WWW::iDRAC->new( host => 'idrac.example.org', username => 'root' ) }, 'WWW::iDRAC::Error::Validation', 'the password is required' );
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

  my $conflict = error_of { WWW::iDRAC->new( host => 'idrac.example.org', %login, verify_ssl => 0, ssl_fingerprint => 'sha256$ab12' ) };
  isa_ok( $conflict, 'WWW::iDRAC::Error::Validation', 'verify_ssl => 0 with ssl_fingerprint' );
  like( "$conflict", qr/drops the pin/, 'and why' );
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

subtest 'the SSH side' => sub {
  my $idrac = WWW::iDRAC->new( host => 'idrac.example.org:8443', %login );
  ok( !$idrac->has_racadm, 'racadm is not built before it is asked for' );
  my $racadm = $idrac->racadm;
  isa_ok( $racadm, 'WWW::iDRAC::Racadm' );
  is( $racadm->host, 'idrac.example.org', 'the HTTPS port is not the SSH port' );
  is( $racadm->port, 22, 'SSH is on 22' );
  is( $racadm->username, 'root', 'the same login by default' );
  is( $racadm->password, 'calvin', 'also the password' );
  ok( $racadm->verify_host_key, 'the host key is verified' );
  ok( $racadm->enabled, 'enabled' );
  ok( !$racadm->connected, 'not connected' );

  my $own = WWW::iDRAC->new( host => '[2001:db8::10]:8443', %login, ssh_username => 'ops', ssh_password => 'other', ssh_port => 2222,
    ssh_host_key => 'ssh-ed25519 AAAA', ssh_opts => ['Ciphers=aes256-ctr'], timeout => 20 )->racadm;
  is_deeply( [ $own->host, $own->port, $own->username, $own->password, $own->host_key, $own->timeout ], [ '2001:db8::10', 2222, 'ops', 'other', 'ssh-ed25519 AAAA', 20 ], 'its own login, port and key' );
  is_deeply( $own->ssh_opts, ['Ciphers=aes256-ctr'], 'extra options' );
  ok( !WWW::iDRAC->new( host => 'idrac.example.org', %login, ssh => 0 )->racadm->enabled, 'ssh => 0 reaches the transport' );
  ok( !WWW::iDRAC->new( host => 'idrac.example.org', %login, ssh_verify_host_key => 0 )->racadm->verify_host_key, 'so does ssh_verify_host_key' );
  is( WWW::iDRAC->new( host => 'idrac.example.org', %login, ssh_known_hosts => '/etc/h' )->racadm->known_hosts, '/etc/h', 'and ssh_known_hosts' );

  for my $bad ( [ ssh_port => 0 ], [ ssh_port => 70000 ], [ ssh_username => 'ops' ], [ ssh_password => 'x' ],
                [ ssh_verify_host_key => 0, ssh_host_key => 'ssh-ed25519 AAAA' ], [ ssh_verify_host_key => 0, ssh_known_hosts => '/x' ],
                [ ssh_known_hosts => '/x', ssh_host_key => 'ssh-ed25519 AAAA' ] ) {
    isa_ok( error_of { WWW::iDRAC->new( host => 'idrac.example.org', %login, @$bad ) }, 'WWW::iDRAC::Error::Validation', join ' ', map { $_ // '' } @$bad );
  }

  my $fake = FakeRacadm->new;
  my $with = WWW::iDRAC->new( host => 'idrac.example.org', %login, racadm => $fake->transport );
  is( $with->bios->racadm, $with->racadm, 'the capability classes share the transport' );
  is( $with->jobs->racadm, $with->racadm, 'all of them' );
  is( $with->virtual_media->racadm, $with->racadm, 'all of them' );
  is( $with->bios->get('BiosBootSettings.BootMode'), 'Bios', 'and reach the controller' );
  ok( $fake->connected, 'connected' );
  is( $with->logout, 1, 'logout closes the SSH connection too' );
  ok( !$fake->connected, 'closed' );
  is( $with->logout, 0, 'and says there was nothing the second time' );
  my $idle = WWW::iDRAC->new( host => 'idrac.example.org', %login, ua => FakeiDRAC->new );
  $idle->system->info;
  is( $idle->logout, 1, 'with a Redfish session only' );
  ok( !$idle->has_racadm, 'racadm never built' );
};

done_testing;
