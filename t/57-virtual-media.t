#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use FakeRacadm;
use iDRACShapes;
use WWW::iDRAC;

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

sub setup {
  my ( %arg ) = @_;
  my $racadm = FakeRacadm->new(%arg);
  my $idrac  = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, racadm => $racadm->transport );
  return ( $idrac, $racadm );
}

subtest 'status' => sub {
  my ( $idrac, $fake ) = setup();
  my $status = $idrac->virtual_media->status;
  shape_ok( $status, 'virtual_media.status' );
  is_deeply( $status, { connected => 0, share => undef, username => undef, attach_mode => 'AutoAttach', boot_once => 0, enabled => 1 }, 'no image' );
  is_deeply( $fake->commands, [ 'racadm remoteimage -s', 'racadm get iDRAC.VirtualMedia' ], 'two commands' );

  my ($unlicensed) = setup( licensed => 0 );
  $status = $unlicensed->virtual_media->status;
  is_deeply( $status, { connected => 0, share => undef, username => undef, attach_mode => undef, boot_once => undef, enabled => undef }, 'without the license the configuration is undef and it works' );

  is_deeply( WWW::iDRAC::VirtualMedia->status_from(
      "Remote File Share is Enabled\nUserName  isos\nPassword \nShareName //files.example.org/isos/rescue.iso\n", undef ),
    { connected => 1, share => '//files.example.org/isos/rescue.iso', username => 'isos', attach_mode => undef, boot_once => undef, enabled => undef },
    'an attached image; the password is not returned' );
  is_deeply( WWW::iDRAC::VirtualMedia->status_from( undef, undef ), { connected => undef, share => undef, username => undef, attach_mode => undef, boot_once => undef, enabled => undef }, 'nothing' );
};

subtest 'connect and disconnect' => sub {
  my ( $idrac, $fake ) = setup();
  my $status = $idrac->virtual_media->connect( location => 'https://images.example.org/rescue.iso' );
  is( $fake->commands->[0], 'racadm remoteimage -c -l https://images.example.org/rescue.iso', 'an http location, no user' );
  is( $status->{connected}, 1, 'connected afterwards' );
  is( $status->{share}, 'https://images.example.org/rescue.iso', 'the share' );

  $idrac->virtual_media->connect( location => '//files.example.org/my isos/rescue.iso', username => 'isos', password => 'p4ss word' );
  is( $fake->commands->[-3], 'racadm remoteimage -c -u isos -p "p4ss word" -l "//files.example.org/my isos/rescue.iso"', 'a CIFS share with quoting' );
  $idrac->virtual_media->connect( location => 'nfs.example.org:/export/rescue.iso' );
  is( $fake->commands->[-3], 'racadm remoteimage -c -l nfs.example.org:/export/rescue.iso', 'an NFS export' );

  $status = $idrac->virtual_media->disconnect;
  is( $fake->commands->[-3], 'racadm remoteimage -d', 'disconnect' );
  is( $status->{connected}, 0, 'and it is gone' );
};

subtest 'what connect refuses' => sub {
  my ( $idrac, $fake ) = setup();
  my %case = (
    'no location'               => [],
    'a location with a quote'   => [ location => '//h/s"x.iso', username => 'u', password => 'p' ],
    'a location with a pipe'    => [ location => 'http://h/a.iso|x' ],
    'a location that is a path' => [ location => '/etc/passwd' ],
    'ftp'                       => [ location => 'ftp://h/a.iso' ],
    'a user without password'   => [ location => 'http://h/a.iso', username => 'u' ],
    'a password without user'   => [ location => 'http://h/a.iso', password => 'p' ],
    'CIFS without credentials'  => [ location => '//h/s/a.iso' ],
    'a password with a quote'   => [ location => 'http://h/a.iso', username => 'u', password => 'p"q' ],
    'a password with a dollar'  => [ location => 'http://h/a.iso', username => 'u', password => 'p$q' ],
    'an option'                 => [ location => 'http://h/a.iso', speed => 1 ],
    'an NFS host that is an option' => [ location => '-f:/export/a.iso' ],
    'a user that is an option'  => [ location => '//h/s/a.iso', username => '-d', password => 'p' ],
    'a password that is an option' => [ location => '//h/s/a.iso', username => 'u', password => '-f' ],
  );
  for my $name ( sort keys %case ) {
    my $e = error_of { $idrac->virtual_media->connect( @{ $case{$name} } ) };
    isa_ok( $e, 'WWW::iDRAC::Error::Validation', $name );
    unlike( "$e", qr/p"q|p\$q/, 'and the password is not in the message' ) if $name =~ /password with/;
  }
  is_deeply( $fake->commands, [], 'nothing was sent for any of them' );
};

subtest 'a controller without the license' => sub {
  my ($idrac) = setup( licensed => 0 );
  ok( $idrac->virtual_media->supports('status'), 'status is there' );
  ok( !$idrac->virtual_media->supports('connect'), 'connect is not' );
  my $e = error_of { $idrac->virtual_media->connect( location => 'http://h/a.iso' ) };
  isa_ok( $e, 'WWW::iDRAC::Error::Unsupported', 'connect' );
  is( $e->capability, 'virtual_media.connect', 'by name' );
  like( $e->reason, qr/license/, 'because of the license' );
};

subtest 'the password is no part of a message' => sub {
  my $fake = FakeRacadm->new( replies => {
    'racadm remoteimage -c -u isos -p Sup3rSecret -l //h/s/a.iso' => "ERROR: RAC1100: cannot log in as isos with Sup3rSecret\n",
  } );
  my $idrac = WWW::iDRAC->new( host => 'idrac.test', username => 'root', password => 'calvin', ua => FakeiDRAC->new, racadm => $fake->transport );
  my $e = error_of { $idrac->virtual_media->connect( location => '//h/s/a.iso', username => 'isos', password => 'Sup3rSecret' ) };
  isa_ok( $e, 'WWW::iDRAC::Error::API' );
  unlike( "$e", qr/Sup3rSecret/, 'not in it' );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
